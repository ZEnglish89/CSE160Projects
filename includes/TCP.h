#ifndef TCP_H
#define TCP_H

#include "packet.h"

// Header for TCP packets/segments.
// Attempting to match the diagram from page 379 of the textbook as best as possible, ommitting a few fields
// for the sake of convenience(for example, if we are intended to implement a checksum that's definitely something
// that I will be doing another day, not right this moment). No variable options field and therefore no headerLength,
// at least not at this stage of the project.
typedef nx_struct TCPHeader {
    nx_uint16_t SrcPort;    // The port in the source Node which this connection is using
    nx_uint16_t DestPort;   // Guess.
    nx_uint32_t SeqNum;     // Sequence Number
    nx_uint32_t ACK;        // Acknowledgement field. For both SeqNum and ACK the textbook specifies 32-bits, so I'm using that here.
    
    // The six possible FLAG fields. I've included them as separate variables rather than one 6-bit field for clarity.
    // It could potentially have been better to have them as bools rather than one-bit integers, but I'm not sure if there's
    // a meaningful difference and this keeps them represented by the same data type as every other field.
    nx_uint1_t SYN;
    nx_uint1_t FIN;
    nx_uint1_t RESET;
    nx_uint1_t PUSH;
    nx_uint1_t URG;
    nx_uint1_t ACK;
    
    nx_uint16_t AdvWindow;  // AdvertisedWindow field
    nx_uint16_t UrgPtr;     // Urgent Data Pointer. Frankly I'm not sure if I understand the use case for this but there is a chance it could be useful to include.
} TCPHeader;

#define TCP_HEADER_SIZE sizeof(TCPHeader)

#endif