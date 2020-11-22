//
//  File.swift
//  
//
//  Created by Jim Studt on 11/20/20.
//

import Foundation

import Crypto
import NIO
import NIOSSH

public protocol SSHPasswordDelegate {
    func authenticate( username:String, password:String, completion: ((Bool)->Void) )
}
public protocol SSHPublicKeyDelegate {
    func authenticate( username:String, publicKey:SSHConsole.PublicKey, completion: ((Bool)->Void) )
}

public class SSHConsole {
    public enum ProtocolError : Error {
        case invalidChannelType
        case invalidDataType
    }

    let host : String
    let port : Int
    let hostKeys : [ NIOSSHPrivateKey ]
    let authenticationDelegate : NIOSSHServerUserAuthenticationDelegate
    let group : MultiThreadedEventLoopGroup = .init(numberOfThreads: 1)
    var channel : Channel? = nil
    
    public init( host:String = "0.0.0.0", port: Int = 2222, hostKeys : [ PrivateKey ], passwordDelegate : SSHPasswordDelegate? = nil, publicKeyDelegate : SSHPublicKeyDelegate? = nil ) {
        
        self.host = host
        self.port = port
        self.hostKeys = hostKeys.map{ $0.key}
        self.authenticationDelegate = AuthenticationDelegate(passwordDelegate: passwordDelegate, publicKeyDelegate: publicKeyDelegate)
    }
    deinit {
        try? group.syncShutdownGracefully()
    }
    
    public func listen( handlerType:SSHConsole.CommandHandler.Type ) throws {
        func sshChildChannelInitializer(_ channel: Channel, _ channelType: SSHChannelType) -> EventLoopFuture<Void> {
            switch channelType {
            case .session:
                return channel.pipeline.addHandler( handlerType.init() )
            default:
                return channel.eventLoop.makeFailedFuture(ProtocolError.invalidChannelType)
            }
        }
        
        let bootstrap = ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                _ = channel.setOption(ChannelOptions.allowRemoteHalfClosure, value:true)
                return channel.pipeline.addHandlers([NIOSSHHandler(role: .server(.init(hostKeys: self.hostKeys,
                                                                                       userAuthDelegate: self.authenticationDelegate)),
                                                                   allocator: channel.allocator,
                                                                   inboundChildChannelInitializer: sshChildChannelInitializer(_:_:)),
                                                     ErrorHandler()])
            }
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
        
        channel = try bootstrap.bind(host: "0.0.0.0", port: 2222).wait()
    }
    
    public func stop() throws {
        try channel?.close().wait()
    }
    
    //
    // This appears to exist to poison any data which escapes the NIOSSHHandler
    //
    internal final class ErrorHandler: ChannelInboundHandler {
        typealias InboundIn = Any
        
        func errorCaught(context: ChannelHandlerContext, error: Error) {
            print("Error in pipeline: \(error)")
            context.close(promise: nil)
        }
    }
}

extension SSHConsole {
    internal final class AuthenticationDelegate: NIOSSHServerUserAuthenticationDelegate {
        let passwordDelegate : SSHPasswordDelegate?
        let publicKeyDelegate : SSHPublicKeyDelegate?

        var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods
        
        init( passwordDelegate : SSHPasswordDelegate? = nil, publicKeyDelegate: SSHPublicKeyDelegate? = nil ) {
            self.passwordDelegate = passwordDelegate
            self.publicKeyDelegate = publicKeyDelegate
            
            let pw : NIOSSHAvailableUserAuthenticationMethods = passwordDelegate == nil ? [] : [ .password ]
            let pk : NIOSSHAvailableUserAuthenticationMethods = publicKeyDelegate == nil ? [] : [ .publicKey ]
            supportedAuthenticationMethods = pw.union(pk)
        }
        
        func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
            // I don't want to leak NIOSSH to our callers, so we do with a simple Bool callback and keep
            // the promises to ourselves.
            let finish = { (_ b:Bool) -> Void in
                responsePromise.succeed( b ? .success : .failure )
            }
            
            switch request.request {
            case .password(let password):
                guard let d = passwordDelegate else { return responsePromise.succeed(.failure) }
                
                d.authenticate(username: request.username, password: password.password, completion: finish)
            case .publicKey(let pubkey):
                guard let d = publicKeyDelegate else { return responsePromise.succeed(.failure) }
                
                d.authenticate(username: request.username, publicKey:PublicKey(key:pubkey), completion: finish)
            default:
                responsePromise.succeed(.failure)
            }
            
        }
    }
}


extension SSHConsole {
    public struct PublicKey {
        let key : NIOSSHUserAuthenticationRequest.Request.PublicKey
        
        public init(key: NIOSSHUserAuthenticationRequest.Request.PublicKey) {
            self.key = key
        }
        
        public func matches( openSSHPublicKey:String) -> Bool {
            guard let k = try? NIOSSHPublicKey.init(openSSHPublicKey: openSSHPublicKey) else { return false }
            return k == self.key.publicKey
        }
        
        public func isIn( file:String) -> Bool {
            return file.split(separator: "\n")
                .map{ $0.trimmingCharacters(in: .whitespacesAndNewlines)}
                .contains { self.matches(openSSHPublicKey: $0) }
        }
    }

    public struct PrivateKey {
        var key : NIOSSHPrivateKey { NIOSSHPrivateKey(ed25519Key: _key) }
        public var string : String { "ed25519 \(_key.rawRepresentation.base64EncodedString())" }
        
        private let _key : Curve25519.Signing.PrivateKey
        
        public init() {
            _key = Curve25519.Signing.PrivateKey()
        }
        
        public init?( string:String) {
            let parts = string.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            
            if parts.count < 2 { return nil }

            guard let data = Data( base64Encoded:String(parts[1])) else { return nil }

            switch parts[0] {
            case "ed25519":
                guard let hk = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else { return nil }
                _key = hk
            default:
                return nil
            }
        }
    }

}
