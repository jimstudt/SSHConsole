//
//  CommandHandler.swift
//  
//  Created by Jim Studt on 11/20/20.
//
//  SPDX-License-Identifier: MIT
//

import Dispatch
import Foundation
import NIO
import NIOSSH

extension SSHConsole {
    
    /// The command handler for an SSHConsole connection.
    ///
    public class CommandHandler: ChannelDuplexHandler {
        public typealias InboundIn = SSHChannelData
        public typealias InboundOut = ByteBuffer
        public typealias OutboundIn = ByteBuffer
        public typealias OutboundOut = SSHChannelData
        
        public let runner : Runner
        public let user : String
        
        private let queue = DispatchQueue(label: "ssh sync")
        private var environment: [String: String] = [:]
        
        private var madeStream : Bool = false
        private weak var _outputStream : Output? = nil
        
        public required init(runner: @escaping Runner, user:String) {
            self.runner = runner
            self.user = user
        }
        
        //
        // This is a bit odd. You can take a bunch of these, when the last one
        // goes, then we get closed. In practice I think people will only make
        // one, but this semantic lets me avoid communicating an error if they
        // call more than once.
        //
        internal var outputStream : Output {
            if let stream = _outputStream { return stream }
            
            if madeStream { fatalError("remaking an outputStream")}
            madeStream = true
            
            let s = Output(handler: self)
            _outputStream = s
            return s
        }
        
        weak var context : ChannelHandlerContext? = nil
        
        //
        // Always turn on our .allowRemoteHalfClosure because SSH needs it.
        //
        public func handlerAdded(context: ChannelHandlerContext) {
            self.context = context        // save it for writing later
            context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { error in
                context.fireErrorCaught(error)
            }
        }
        
        public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
            switch event {
            case let event as SSHChannelRequestEvent.ExecRequest:
                // Change to a whenSuccess when UsernameOption() support is integrated in NIOSSH main release
                context.channel.getOption( SSHChildChannelOptions.Types.UsernameOption()).whenComplete{ result in
                    switch result {
                    case .failure(_):
                        self.runner( event.command, self.outputStream, nil, self.environment)
                    case .success(let username):
                        self.runner( event.command, self.outputStream, username, self.environment)
                    }
                }
                
            case let event as SSHChannelRequestEvent.EnvironmentRequest:
                self.queue.sync {
                    environment[event.name] = event.value
                }
                
            default:
                context.fireUserInboundEventTriggered(event)
            }
        }
        
        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let data = self.unwrapInboundIn(data)
            
            /*
             guard case .byteBuffer(let bytes) = data.data else {
             fatalError("Unexpected read type")
             }
             */
            guard case .channel = data.type else {
                context.fireErrorCaught(SSHConsole.ProtocolError.invalidDataType)
                return
            }
            
            let buf = context.channel.allocator.buffer(string: "Input Not Accepted\n\r")
            
            let prom = context.eventLoop.makePromise(of:Void.self)
            prom.futureResult.whenComplete( { _ in _ = context.close() })
            
            writeError(context:context, data:NIOAny(buf), promise: prom)
            //context.fireChannelRead(self.wrapInboundOut(bytes))
        }
        
        public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
            let data = self.unwrapOutboundIn(data)
            context.writeAndFlush(self.wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(data))), promise: promise)
        }
        
        public func writeError(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
            let data = self.unwrapOutboundIn(data)
            
            context.writeAndFlush(self.wrapOutboundOut( SSHChannelData(type: .stdErr, data: .byteBuffer(data))), promise: promise)
        }
        
    }
}

extension SSHConsole.CommandHandler {
    public func write(text: String, promise: EventLoopPromise<Void>?) {
        guard let c = context else { return }
        
        c.eventLoop.execute {
            let buf = c.channel.allocator.buffer(string: text)

            self.write(context: c, data: NIOAny(buf), promise: promise)
        }
    }

    public func writeError(text: String, promise: EventLoopPromise<Void>?) {
        guard let c = context else { return }
        
        c.eventLoop.execute {
            let buf = c.channel.allocator.buffer(string: text)

            self.writeError(context: c, data: NIOAny(buf), promise: promise)
        }
    }

   //
    // Flush and close
    //
    public func close( promise: EventLoopPromise<Void>?) {
        guard let c = context else { return }
        
        c.eventLoop.execute {
            c.flush()
            c.close(promise: promise)  // does this need to wait for the flush and write?
        }
    }
    
    /// An output stream for sending data back to the SSH client.
    public class Output : TextOutputStream {
        private let handler : SSHConsole.CommandHandler
        
        internal init( handler: SSHConsole.CommandHandler ) {
            self.handler = handler
        }
        deinit {
            handler.close(promise: nil)
        }
        /// Send data back to the client
        ///
        /// You will probably want to end lines with "\r\n" to make terminal clients do the right thing.
        ///
        /// This output may be buffered arbitrarily long until you finish your command and release
        /// the Output object.
        ///
        /// - Parameter string: Text to send
        public func write(_ string: String) {
            handler.write(text:string, promise: nil)
        }
        
        /// Send data back to the client on its standard error stream
        ///
        /// You will probably want to end lines with "\r\n" to make terminal clients do the right thing.
        ///
        /// This output may be buffered arbitrarily long until you finish your command and release
        /// the Output object.
        ///
        /// - Parameter string: Text to send
        public func writeError(_ string: String) {
            handler.writeError(text:string, promise: nil)
        }
   }

}
