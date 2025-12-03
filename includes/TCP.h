#ifndef TCP_H
#define TCP_H

#include "packet.h"
#include "socket.h"

// Header for TCP packets/segments.
typedef nx_struct TCPHeader {
    nx_uint16_t SrcPort;    // The port in the source Node which this connection is using
    nx_uint16_t DestPort;   // Destination port
    nx_uint32_t SeqNum;     // Sequence Number
    nx_uint32_t AckNum;     // Acknowledgement number
    
    nx_uint8_t flags;       // Flags: bit 0=SYN, bit 1=FIN, bit 2=RESET, bit 3=PUSH, bit 4=URG, bit 5=ACK
    nx_uint8_t reserved;    // Reserved for future use
    
    nx_uint16_t AdvWindow;  // AdvertisedWindow field
    nx_uint16_t UrgPtr;     // Urgent Data Pointer
} __attribute__((packed)) TCPHeader;

#define TCP_HEADER_SIZE sizeof(TCPHeader)

// Flag masks
#define TCP_FLAG_SYN   0x01
#define TCP_FLAG_FIN   0x02
#define TCP_FLAG_RESET 0x04
#define TCP_FLAG_PUSH  0x08
#define TCP_FLAG_URG   0x10
#define TCP_FLAG_ACK   0x20

#endif