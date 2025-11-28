//some of these includes are likely unnecessary, but it's more important to me
//to get everything we need than to avoid things we don't.

#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"
#include "../../includes/IP.h"
#include "../../includes/TCP.h"
#include "../../includes/socket.h"

module TCPP{
    provides interface TCP;

    uses interface IP;


implementation{

    socket_store_t activeSockets[65536]; //there's no way we'll keep this value, but it's a decent base to have potentially as many sockets as there are ports.
    //we could then theoretically hash the sockets based on their port number, and avoid having to do any linear searches during operation?
    //there may be an issue with doing that, I'm not sure.

    command void TCP.connect(uint16_t dest, uint16_t srcPort, uint16_t destPort){
        
        //set up a new socket with the appropriate information.
        socket_store_t newSocket;
        TCPHeader head;

        newSocket.state = CLOSED;
        newSocket.src = srcPort;
        newSocket.dest.addr = dest;
        newSocket.dest.port = destPort;

        head.SrcPort = srcPort;
        head.DestPort = destPort;
        head.SeqNum = 0; //I'm not sure how to handle this? consider it a placeholder I suppose.
        head.SYN = 1;
        head.FIN = 0;
        head.RESET = 0;
        head.PUSH = 0;
        head.URG = 0;
        head.ACK = 0;
        //maybe it would be more efficient to replace the six separate fields with one field with six options, and just assign one to each option.
        //would likely be more bit-efficient too.
        head.AdvertisedWindow = 1; //idk man
        head.UrgPtr = 0; //just leave this zero, we will be ignoring it unless the flag is set anyway.

        call TCP.sendSegment(newSocket,&head,TCP_HEADER_SIZE);

        newSocket.state = SYN_SENT;
        //at this point, we should save newSocket into the activeSockets list. I'm not sure if we should just copy over, or pass in as a pointer.
    }
    
    command void TCP.sendSegment(socket_store_t socket, uint8_t *payld,uint8_t pld_len){
        //This guy will have to undergo a LOT of revision. Do we need to account for the sliding window here, or should we
        //assume its already handled by the time we get here? Right now I'm assuming it's fine.
        pack msg;
        memcpy(msg.payload,payld,pld_len);

        IP.sendMessage(socket.dest.addr,&msg,PROTOCOL_TCP);

        return;
    }

    command void TCP.handleSegment(pack* msg, uint8_t pktLen){
        //similarly, this will need a lot of work. Should we have IP pull any information for us, or just have it hand over the packet payload and
        //handle the rest ourselves?
        //probably the latter, because there's no point in making IP do part of TCP's functionality, and we don't really gain anything from doing that.

        TCPHeader head;
        socket_store_t Socket;
        //Maybe make this a socket POINTER, and just set it equal to the appropriate one from the list?

        memcpy(head,msg,TCP_HEADER_SIZE);

        //using the source and destination ports and addresses within head, find the appropriate socket out of the list of active sockets.

        //we'll need more checks than just whether or not this is an ACK, but for now...
        if(head.ACK!=1){
            //if this isn't an ACK, read the actual payload into the received buffer of the appropriate Socket.
            memcpy(Socket.rcvdBuff,msg[TCP_HEADER_SIZE],pktLen-TCP_HEADER_SIZE);
        }

        return;
    }
    
}