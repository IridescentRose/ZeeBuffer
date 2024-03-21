# ZeeBuffers

ZeeBuffers is a protocol for serializing and deserializing data in a stateful client-server connection. It is designed to be simple, fast, and easy to implement. It is designed to be used in a wide variety of applications, from embedded systems to high-performance servers. 

# Usage

The [protocol](./PROTOCOL.MD) is defined in the `.zb` protocol file. This protocol is a single file that defines the messages that can be sent between the client and server. The protocol file is then compiled to the target language using the `zb` compiler. The compiler generates code that can be used to send and receive messages in the target language.

To use in the target language you must pass a function to send or receive data, making ZeeBuffers compatible with any transport layer. ZeeBuffers does not handle the transport layer, only the serialization and deserialization of messages; decisions about how to send and receive data are left to the user. 

The protocol when compiled to your target language allows you to register listeners or "routes" that are called when a message is received. This lets you declaratively define a server or client that can handle messages without needing to write a lot of boilerplate code.

ZeeBuffers has an optional support for generating basic client and server implementations using network sockets. This is useful for testing and prototyping, but it is not recommended for production use, or advanced use cases.

# ¿Parker Jones?

Thank you for helping design the protocol!