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
    /// You will subclass this and override the `doCommand` method.
    /// Later I will probably break this API, but it won't take long for you to adapt.
    ///
    open class CommandHandler: ChannelDuplexHandler {
        public typealias InboundIn = SSHChannelData
        public typealias InboundOut = ByteBuffer
        public typealias OutboundIn = ByteBuffer
        public typealias OutboundOut = SSHChannelData
        
        private let queue = DispatchQueue(label: "ssh sync")
        private var environment: [String: String] = [:]
        
        private var madeStream : Bool = false
        private weak var _outputStream : Output? = nil
        
        public required init() {}
        
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
        
        /// Act upon an SSH command, possibly sending output and errors back to the client.
        ///
        /// Respond to the `command`. Output can be sent back with `to.write(_)` and `to.writeError(_)`.
        /// This may be buffered until you finish and release all references to `to`, which naturally happens unless
        /// you do something exceptionally "clever".
        ///
        /// You will implement this in your subclass of CommandHandler.
        ///
        /// No input can be transmitted from the SSH client. Only the command.
        ///
        /// - Attention: Get off of this thread. Use Dispatch or EventLoop to run somewhere else if
        /// your command takes *any* time.
        ///
        /// - Parameters:
        ///   - command: The command from SSH
        ///   - to: an Output object to send data back to the client
        ///   - environment: A dictionary of the environment variables sent by the client
        ///
        open func doCommand( command:String, to:Output, environment:[String:String]) {
            to.write("\(Self.Type.self) has no doCommand to do: \(command)")
        }
        
        public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
            switch event {
            case let event as SSHChannelRequestEvent.ExecRequest:
                doCommand( command:event.command, to:outputStream, environment:environment)
                
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

            print("SSHTextOutputStream closes: \(ObjectIdentifier(self)) - \(handler)")
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
