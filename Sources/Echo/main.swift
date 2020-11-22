//
//  Echo Example for SSHConsole - main.swift
//  
//  Created by Jim Studt on 11/21/20.
//
//  SPDX-License-Identifier: MIT
//

import Foundation
import SSHConsole
import Dispatch

///
/// This conforms to the `SSHPublicKeyDelegate` protocol and enables public key authentication.
///
/// This one's policy is to look in the process owner's `~/.ssh/authorized_keys` file for a
/// OpenSSH formatted key, which SwiftNIO SSH can handle (no RSA), that matches the `publicKey`.
///
/// - Attention: `completion()` must be called exactly once.
///
/// - Note: You probably want to push this off onto a work queue somewhere if it does file I/O like this one.
///
struct Authenticator : SSHPublicKeyDelegate {
    //
    // Scan the user's ~/.ssh/authorized_keys file for OpenSSH format keys
    // Ignore username, we know who we are.
    //
    // Not all formats are supported, like RSA apparently. ssh-ed25519 is.
    //
    func authenticate( username:String, publicKey:SSHConsole.PublicKey, completion: @escaping ((Bool)->Void)) {
        DispatchQueue.global().async {
            let homeDirURL = FileManager.default.homeDirectoryForCurrentUser
            let authorizedKeysURL = URL(fileURLWithPath: ".ssh/authorized_keys", relativeTo: homeDirURL)
            
            if let file = try? String(contentsOfFile: authorizedKeysURL.path) {
                //
                // The actual work: We are passing the entire file to publicKey.isIn(file:)
                completion( publicKey.isIn(file:file))
            }
            return completion(false)
        }
    }
}

///
/// Implement a password policy. This one is especially terrible and you should not do this.
///
/// There is a single authorized user named *password* with a password of *admin*. Just
/// confusing enough to shake the stupid bots if they crawl you while running the example.
///
/// Your `ssh` command won't offer a password unless it fails at public key authentication.
/// Your `ssh` command might let you add a ` -o PubkeyAuthentication=no` to
/// forgo your public key and let you test passwords.
///
/// - Attention: `completion()` must be called exactly once.
///
/// - Warning: You probably don't want to put hardcoded passwords in your source code.
///            Someone will find it in a repository.
///
/// - Note: You probably want to push this off onto a work queue somewhere if it does file I/O like this one.
///
struct TrivialPassword : SSHPasswordDelegate {
    func authenticate(username: String, password: String, completion: @escaping ((Bool) -> Void)) {
        
        DispatchQueue.global().async {
            completion( username == "password" && password == "admin")
        }
    }
}

///
/// You will need something which implements `SSHConsole.CommandHandler` to
/// dispatch your commands. This is the one for the Example. It implements a simple
/// `echo` server with the twist that if you send `exit ` it will cleanly exit the server.
///
/// In practice, I feed these to an augmented Swift Argument Parser, but that is work for
/// another repository, I don't want to pollute this one.
///
class DoCommand : SSHConsole.CommandHandler {
    
    /// Process a command from an SSH connection. SSHConsole does not accept input, so this is the
    /// command part of the `ssh` command as one solid string.
    ///
    /// - Parameters:
    ///   - command: The command from the SSH session
    ///   - to: Use this to send output or error back to the remote SSH client
    ///   - environment: The environment variables sent by the SSH client
    ///
    /// You will want to get off onto your own work queue to do the work. Don't hang up SSHConsole's
    /// thread. It is left to you since SSHConsole doesn't know what your app uses and maybe you have
    /// synchronization issues.
    ///
    /// - Attention: The SSH output is flushed and the connection closed when the `to` parameter
    ///              deinitializes. If you hold a reference after your command is done, then your command
    ///              is *not* done. In practice this takes care of itself unless you are too clever.
    ///
    override func doCommand(command: String, to: SSHConsole.CommandHandler.Output, environment: [String : String]) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        DispatchQueue.global().async {
            switch trimmed {
            case "exit":
                to.write("Goodbye\r\n")
                terminate.signal()
            default:
                to.write("echo: \(trimmed)\r\n")
            }
        }
    }
}

///
/// When this semaphore is signalled, we will cleanly terminate the program.
///
let terminate = DispatchSemaphore(value: 0)

///
/// Please excuse the "!", this is a demo. You will need to first make one, then store it somewhere, then
/// retrieve it at startup in your real code.
///
/// Something like `saveMyNewKey( SSHConsole.PrivateKey().string )` will get you your own key.
/// You might just print it in the debugger and paste it in like this for testing.
///
let hostKeys = [ SSHConsole.PrivateKey(string:"ed25519 IWK76Glc2Dh7BeaSJrErVAndP6QWHZ06Wk9U5aeoaEI=")! ]

///
/// At last! We create our console on our port with out identity and security policy., then start listening with our command handler.
///
let console = SSHConsole( port:2525, hostKeys:hostKeys, passwordDelegate: TrivialPassword() , publicKeyDelegate: Authenticator() )
try console.listen( handlerType:DoCommand.self )

///
/// Hang around and let things happen. Eventually someone will send an `exit` command and
/// this will return.
///
/// Notice that this is *your* program doing the waiting it *its* own special way. Nothing to do with SSHConsole.
///
terminate.wait()

///
/// Do a clean shutdown
///
try console.stop()

print("Echo is done.")
