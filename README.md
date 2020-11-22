# SSHConsole

A simple command console for servers using [SwiftNIO SSH]("https://github.com/apple/swift-nio-ssh").

## Why Would I Use This?

This package provides a SSH listener to your server which allows you to `ssh` commmands to your server 
and receive the response back to your terminal.

You might use this to report on your server's internals, issue tuning commands, or tell it to restart or shutdown.

It is MIT licensed. Go wild.

## How Much Work is This?

Just **three** lines of code.

Plus 5 to manage your *host key* so you don't annoy yourself by having to approve a new one 
each time you restart your server.

Plus 10 more to have some sort of responsible authentication.

Plus however you do your commands. I use [Swift Argument Parser](https://github.com/apple/swift-argument-parser) to define 
my commands, which is great, but not quite intended to be used this way and there is a page of extensions required 
to work around it's limitations. But strictly speaking, that's not part of this project and you can do whatever you 
want with your commands. I'll put it in an example server for you to copy if you want.

## Show Me.

```swift
import SSHConsole

/// get your program doing it's stuff

let console = SSHConsole( port:2525, hostKeys:hostKeys, passwordDelegate: TrivialPassword() , publicKeyDelegate: Authenticator() )
try console.listen( handlerType:DoCommand.self )

/// wait around in your program until you are ready to exit

try console.stop()   // Or don't, but this flushes and closes the open sockets
```

Ok, I've lied there. You will notice that `TrivialPassword()` seems like a really bad idea, `Authenticator()`
is not defined, and I left `DoCommand` as an exercise to the reader. But go look in the example Echo server. The
whole think *with* all the missing bits as ~130 lines and thats mostly comments for you.

Here is the [complete source for the Echo server](https://github.com/jimstudt/SSHConfig/Echo/main.swift)

> I'll put a sample server here, when I write one.

## How Much Does This Drag In?

- [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh)

- SwiftNIO SSH will then drag in [SwiftNIO](https://github.com/apple/swift-nio/), and 
  [Swift Crypto](https://github.com/apple/swift-crypto) but you 
  probably already have them if you are writing a server.

## It Looks Small, What Kind of Limitiations Does It Have?

- It only does commands with no input. If you try to send input it will chastise you and destroy your 
  sockets. I thought about adding sessions, but that is more code than the whole thing now, 
  and if I give you that you'll want command line editting and recall, and well, it all can get out of hand 
  in a hurry. There is a utility which lets you edit commands locally and ship them off on enter. 
  But I've forgotten the name. Still, it would be great with this.

- It doesn't handle RSA keys. This is a, possibly permanent, limitation of the SwiftNIO SSH project.

- It only does ED25519 server keys. This can be expanded, but I'm annoyed at Swift NIO blinding 
  me to the private keys and I'm hoping they'll open that up and I won't have to write the 20 lines of
  code to expand my shadow private key logic I use to work around the blinding.

## How Stable is the API?

Not at all. In fact, I'll probably stop this subclassing nonesense and make `listen`  take a delegate 
object or maybe just a function for the "handle a command" function.

## How Committed Is The Maintainer?

Not at all. This is a two-day rathole I ran down for my own servers. I'll use it and probably spend
another day polishing it, but if you are a sizeable organization or active developer and want to use it, 
maybe I should give it to you. (I also vanish for months at a time, so responses are not timely.) – *fork is your friend*

## What's Next?

- Write the API documentation.

- Test on Linux. I think it works.

- There isn't a mechanism to report *who* the authorized user is to your command handler.
  I don't care, I don't have different classes of users, but I can see where one might.
  
