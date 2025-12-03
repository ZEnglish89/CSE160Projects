#ifndef __SOCKET_H__
#define __SOCKET_H__

enum{
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,
    NULL_SOCKET = 255,
};

// TCP State Machine States
enum socket_state{
    CLOSED,
    LISTEN,
    SYN_SENT,
    SYN_RCVD,
    ESTABLISHED,
    FIN_WAIT_1,
    FIN_WAIT_2,
    CLOSING,
    TIME_WAIT,
    CLOSE_WAIT,
    LAST_ACK
};

typedef nx_uint16_t nx_socket_port_t;
typedef uint16_t socket_port_t;

// socket_addr_t is a simplified version of an IP connection.
typedef nx_struct socket_addr_t{
    nx_socket_port_t port;
    nx_uint16_t addr;
}socket_addr_t;

// File descripter id. Each id is associated with a socket_store_t
typedef uint8_t socket_t;

// State of a socket. (Complete structure with buffers)
typedef struct socket_store_t{
    uint8_t flag;
    enum socket_state state;
    socket_port_t src;
    socket_addr_t dest;
    
    // Sequence and Acknowledgement Numbers
    uint32_t nextSequence;     // Next sequence number to send
    uint32_t nextExpected;     // Next sequence number expected from peer
    
    // Send buffer for sliding window
    uint8_t sendBuffer[SOCKET_BUFFER_SIZE];
    uint32_t sendBufferStart;  // Start of send buffer (bytes)
    uint32_t sendBufferEnd;    // End of send buffer (bytes)
    uint32_t lastByteSent;     // Last byte sent
    uint32_t lastByteAcked;    // Last byte acknowledged
    
    // Receive buffer for flow control
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
    uint32_t lastByteRead;     // Last byte read by application
    uint32_t lastByteRcvd;     // Last byte received from network
    
    // Flow control
    uint32_t peerWindow;       // Peer's advertised window
    uint32_t effectiveWindow;  // Our current send window
    
    // Retransmission
    uint32_t RTT;              // Estimated round-trip time
    uint32_t RTTVar;           // RTT variation
    uint32_t timeout;          // Current timeout value
    
    // Connection management
    uint32_t timeWaitCount;    // TIME_WAIT timer
    
    // Timer for retransmissions
    uint32_t retransmitTime;   // Time of last transmission
}socket_store_t;

#endif