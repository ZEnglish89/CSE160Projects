//Grabbing a bunch of inclusions because I already had the list on-hand from
//another file and I don't want to risk missing anything.

#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/IP.h"

module IPP{
    provides interface IP;

    uses interface SimpleSend;
    uses interface Flooding;
    uses interface LinkState;
}

implementation{
    command void IP.sendMessage(uint16_t destAddr, uint8_t *payld){
        pack msg;
        //if this is meant to be broadcast, just let Flooding handle it.
        if (destAddr == 0){
            call Flooding.startFlood(destAddr,payld,PACKET_MAX_PAYLOAD_SIZE,PROTOCOL_PING);
            return;
        }

        //otherwise, it's our problem.
        //make a packet and an IP header
        

        IPHeader head;

        //grab the next hop information right away to avoid unnecessary work if we would just have to drop
        //the packet anyway.
        uint8_t uncastedNextHop = call LinkState.getNextHop(destAddr);

        //the nextHop defaults to 0xFF if we haven't found a route.
        if(uncastedNextHop == 0xFF){
            dbg(IP_CHANNEL,"Node %d dropped packet due to no route available\n",TOS_NODE_ID);
            return;
        }

        //cast to match the packet header's requirements.
        uint16_t NextHop = (nx_uint16_t) uncastedNextHop;

        //populate the IP header with relevant information. We're sending the message here, so we know that we're the source.
        head.IPSrc = TOS_NODE_ID;
        head.IPDest = destAddr;
        head.IPTTL = MAX_TTL;
        //the protocol is subject to change later, right now we'll just default to Ping
        head.IPProtocol = PROTOCOL_PING;

        //copy the IP header into the front of the packet's payload space.
        memcpy(msg.payload,&head,IP_HEADER_SIZE);

        //copy the rest of the payload in after the header.
        uint8_t payldLen = PACKET_MAX_PAYLOAD_SIZE - IP_HEADER_SIZE;
        memcpy(msg.payload+IP_HEADER_SIZE,payld,payldLen);

        msg.src = TOS_NODE_ID;
        msg.dest = NextHop;
        //TTL can be 0 because we're only going one hop, sequence number is irrelevant for right now.
        msg.TTL = 0;
        msg.seq = 0;
        msg.protocol = PROTOCOL_PING;

        //now we just send this along the standard sending functionality to its next hop.
        call SimpleSend.send(msg,NextHop);
        return;
        
    }

    command void IP.handleMessage(pack* msg, uint8_t pktLen, uint16_t senderId){

        //create IP Header and copy the header of the incoming packet into it.
        IPHeader head;

        memcpy(&head,msg->payload,IP_HEADER_SIZE);

        uint8_t finalDest = (uint8_t) head.IPDest;

        //check if we're the destination.
        if(finalDest == TOS_NODE_ID){
            dbg(IP_CHANNEL,"Node %d received packet intended for it!\n",TOS_NODE_ID);
            return;
        }

        //if this was a broadcast, just let Flooding handle it.
        if(finalDest == AM_BROADCAST_ADDR){
            call Flooding.handleFloodPacket(msg,pktLen,senderId);
            return;
        }

        //check TTL
        if(head.IPTTL==0){
            dbg(IP_CHANNEL,"Node %d dropping packet due to TTL\n",TOS_NODE_ID);
            return;
        }

        //grab the next hop information right away to avoid unnecessary work if we would just have to drop
        //the packet anyway.
        uint8_t uncastedNextHop = LinkState.getNextHop(finalDest);

        //the nextHop defaults to 0xFF if we haven't found a route.
        if(uncastedNextHop == 0xFF){
            dbg(IP_CHANNEL,"Node %d dropped packet due to no route available\n",TOS_NODE_ID);
            return;
        }

        //cast to match the packet header's requirements.
        nx_uint16_t NextHop = (nx_uint16_t) uncastedNextHop;

        //decrement TTL
        head.IPTTL-=1;

        //if the TTL hasn't bottomed out, copy the new TTL into the packet,
        //set up the standard header again, and send on.
        if(head.IPTTL>0){

            memcpy(msg.payload,&head,IP_HEADER_SIZE);

            msg.src = TOS_NODE_ID;
            msg.dest = NextHop;
            //TTL can be 0 because we're only going one hop, sequence number is irrelevant for right now.
            msg.TTL = 0;
            msg.seq = 0;
            msg.protocol = PROTOCOL_PING;

            //now we just send this along the standard sending functionality to its next hop.
            call SimpleSend.send(msg,NextHop);
            return;
        }
        return;

    }

	event void Flooding.floodReceived(uint16_t floodSource, uint16_t seqNum, uint8_t *payld, uint8_t payldLen) {
	}

	event void Flooding.floodAckReceived(uint16_t source, uint16_t seq) {
	}
}

