/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "../../includes/packet.h"
#include "../../includes/command.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"
#include "../../includes/flooding.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   uses interface Flooding;

   uses interface NeighborDiscovery;
}

implementation{
   pack sendPackage;
   FloodCacheEntry floodCache[MAX_FLOOD_CACHE_ENTRIES];
   uint8_t floodCacheSize = 0;

   void makePack(pack *pkg, uint16_t srcAddr, uint16_t destAddr, uint16_t timeToLive, uint16_t prot, uint16_t seqNum, uint8_t *payld, uint8_t payldLen);
   void handleFloodPacket(pack* receivedPkt, uint8_t pktLen, uint16_t senderId);
   void forwardFloodToNeighbors(pack* floodPkt, uint16_t senderId);
   bool isDuplicateFlood(uint16_t floodSource, uint16_t seqNum);
   void sendFloodAck(uint16_t dest_node, uint16_t seq_num);

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         //As soon as the radio is on, find our neighbors and get ready for potential floods.
         call NeighborDiscovery.findNeighbors();
         call Flooding.initializeFlooding();
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
      //when we get a packet, immediately grab it and prepare for potential responses.
      pack* myMsg;
      pack responseMsg;
      uint8_t responsePayload[14];
      
      if(len == sizeof(pack)) {
         myMsg = (pack*) payload;
         
         // Check if this is a neighbor discovery packet
         if(strncmp((char*)myMsg->payload, "NEIGHBOR_DISC", 13) == 0) {
               dbg(NEIGHBOR_CHANNEL, "Received neighbor discovery from node %d\n", myMsg->src);
               
               // If we're not the sender, add to our neighbor table and respond
               if(myMsg->src != TOS_NODE_ID) {
                  // Send response back
                  responseMsg.src = TOS_NODE_ID;
                  responseMsg.dest = myMsg->src;
                  responseMsg.TTL = 1;
                  responseMsg.protocol = 1;
                  
                  memcpy(responsePayload, "NEIGHBOR_RESP", 13);
                  responsePayload[13] = '\0';
                  memcpy(responseMsg.payload, responsePayload, 14);
                  
                  call Sender.send(responseMsg, myMsg->src);
                  dbg(NEIGHBOR_CHANNEL, "Sent neighbor response to node %d\n", myMsg->src);
                  
                  // Add the sender to our neighbor table
                  call NeighborDiscovery.neighborUpdate(myMsg->src);
               }
               return msg;
         }
         // Check if this is a neighbor discovery response
         else if(strncmp((char*)myMsg->payload, "NEIGHBOR_RESP", 13) == 0) {
               dbg(NEIGHBOR_CHANNEL, "Received neighbor response from node %d\n", myMsg->src);
               
               // Add the responder to our neighbor table
               if(myMsg->src != TOS_NODE_ID) {
                  call NeighborDiscovery.neighborUpdate(myMsg->src);
               }
               return msg;
         }
         // otherwise, this is a flooding packet. based on our current setup, if it's not used for neighbordiscovery it must be a flood.
         else{
               dbg(FLOODING_CHANNEL, "Node %d: Received flooding packet from node %d, handling\n", TOS_NODE_ID, myMsg->src);
               handleFloodPacket(myMsg, len, myMsg->src);
               return msg;
         }
         
      }
      //we shouldn't ever get here, but still.
      dbg(GENERAL_CHANNEL, "Packet Received - Unknown Packet Type %d\n", len);
      return msg;
   }


   void handleFloodPacket(pack* receivedPkt, uint8_t pktLen, uint16_t senderId) {
      uint8_t PayloadLength;
      uint8_t PayloadBuffer[PACKET_MAX_PAYLOAD_SIZE];
      //immediately grab the original source from where it's stored in the payload, because flooding cares about that
      //more than the direct source.
      nx_uint16_t originalSrc;
      memcpy(&originalSrc, receivedPkt->payload, sizeof(nx_uint16_t));
      
      
      dbg(FLOODING_CHANNEL,"Node %d received flood type %d from src %d dest %d seq %d TTL %d via node %d\n", 
          TOS_NODE_ID, receivedPkt->protocol, receivedPkt->src, receivedPkt->dest, receivedPkt->seq, receivedPkt->TTL, senderId);
      
      //Now we have to check all the different reasons why we may want to drop it or treat it special: duplicates, dead TTL, if it's just an ACK, etc.
      // Check for duplicates
      if(isDuplicateFlood(originalSrc, receivedPkt->seq)) {
         dbg(FLOODING_CHANNEL,"Node %d dropping duplicate flood\n", TOS_NODE_ID);
         return;
      }
      
      // Check TTL
      if(receivedPkt->TTL == 0) {
         dbg(FLOODING_CHANNEL,"Node %d dropping flood - TTL expired\n", TOS_NODE_ID);
         return;
      }
      //We drop packets by just... not forwarding them. return early.

      //it could be useful to check the TTL *and* see if it's an ACK or not simultaneously, so we can report what type of flood got dropped.
      //consider for future updates, I suppose.

      // Handle ACK floods
      //the PINGREPLY protocol is for ACKs, while PING is for regular floods. Seems appropriate.
      if(receivedPkt->protocol == PROTOCOL_PINGREPLY) {
         //If we're the destination, we signal that we received it and that's all.
         if(receivedPkt->dest == TOS_NODE_ID) {
            signal Flooding.floodAckReceived(originalSrc, receivedPkt->seq);
            //The ACK got to us, no reason to keep flooding it.
            return;
         }
         
         //Otherwise, forward it further. No need to check TTL because we did that above.
         // Decrement TTL and update the packet
         receivedPkt->TTL--;
         
         //Forward the ACK to everyone except the node who sent it to us, to minimize looping.
         forwardFloodToNeighbors(receivedPkt, senderId);
         dbg(FLOODING_CHANNEL,"Node %d forwarding ACK flood seq %d\n", TOS_NODE_ID, receivedPkt->seq);
         return;
      }
      
      // Handle regular/data floods, now that ACKs are out of the way.
      // Check if this flood is targeted(not a broadcast) and we're not the destination
      if(receivedPkt->dest != 0 && receivedPkt->dest != TOS_NODE_ID) {
         //If it's targeted but we aren't the destination, then we skip all the hard work and move ahead to forwarding it.
         dbg(FLOODING_CHANNEL,"Node %d forwarding targeted flood (not for us)\n", TOS_NODE_ID);
      } else {
         // We are either the destination or it's a broadcast flood, so we have to actually deal with it.
         // assume the payload is its maximum size, because I'm crunched for time and that can be an optimization in the future.
         //should probably define a header-length at some point I suppose.
         PayloadLength = PACKET_MAX_PAYLOAD_SIZE;
         
         // Copy payload to buffer, ta-daa it's ours now.
         //not including the originalSrc that's embedded in the payload.
         memcpy(PayloadBuffer, &receivedPkt->payload[sizeof(nx_uint16_t)], PayloadLength-sizeof(nx_uint16_t));
         
         // Signal application that we received a flood
         signal Flooding.floodReceived(receivedPkt->src, receivedPkt->seq, PayloadBuffer, PayloadLength);

         // If this is a targeted flood and we're the destination, send an ACK in return.
         if(receivedPkt->dest == TOS_NODE_ID) {
            dbg(FLOODING_CHANNEL,"Node %d is destination for targeted flood seq %d, sending ACK\n", 
                TOS_NODE_ID, receivedPkt->seq);
            //make sure we're using the ORIGINAL source for our ACK, so it doesn't just go back to the immediate sender.
            sendFloodAck(originalSrc, receivedPkt->seq);
            // The flood has already reached its destination, so there's no reason to keep forwarding.
            return;
         }
      }
      
      // Decrement TTL and get ready to forward.
      receivedPkt->TTL--;
      
      // Forward to everyone except who sent it to us, just like above.
      forwardFloodToNeighbors(receivedPkt, senderId);
   }

   // Forward a flood packet to all the node's neighbors except the one they received it from.
   void forwardFloodToNeighbors(pack* floodPkt, uint16_t senderId) {
      uint8_t i;
      uint8_t neighborCount;
      uint16_t neighborId;
      bool forwarded = FALSE;
      
      // Update source to be us for the forwarded packets
      floodPkt->src = TOS_NODE_ID;
      
      // Get neighbor count from NeighborDiscovery
      neighborCount = call NeighborDiscovery.getNeighborCount();
      
      // Send to each neighbor except the sender
      for(i = 0; i < neighborCount; i++) {
         neighborId = call NeighborDiscovery.getNeighbor(i);
         //If the neighbor being considered isn't the sender, isn't ourselves, and isn't a broadcast ID
         if(neighborId != senderId && neighborId != TOS_NODE_ID && neighborId != 0) {
            dbg(FLOODING_CHANNEL,"Node %d forwarding flood seq %d to neighbor %d\n", 
                TOS_NODE_ID, floodPkt->seq, neighborId);
            //Then send that bad boy!
            call Sender.send(*floodPkt, neighborId);
            forwarded = TRUE;
         }
      }
      //If we check all of our neighbors and there's nobody to forward it to, then say so and move on.
      if(!forwarded) {
         dbg(FLOODING_CHANNEL,"Node %d has no other neighbors to forward flood seq %d\n", 
             TOS_NODE_ID, floodPkt->seq);
      }
   }

   // Check if we've seen this flood before
   bool isDuplicateFlood(uint16_t floodSource, uint16_t seqNum) {
      uint8_t i;
      for(i = 0; i < floodCacheSize; i++) {
         //if the flood came (originally) from the node we're currently considering.
         if(floodCache[i].nodeId == floodSource) {
            //if we've already seen a sequence number that high or higher from that node, then it's a duplicate.
            if(floodCache[i].maxSeq >= seqNum) {
               return TRUE;
            }
            //if not, it must be new, so we can adjust our max and move on.
            floodCache[i].maxSeq = seqNum;
            return FALSE;
         }
      }
      
      //if we made it all the way through that loop without returning, this must come from a new source, so we can try adding it to the cache.
      if(floodCacheSize < MAX_FLOOD_CACHE_ENTRIES) {
         floodCache[floodCacheSize].nodeId = floodSource;
         floodCache[floodCacheSize].maxSeq = seqNum;
         floodCacheSize++;
      }
      //and if so, it can't possibly be a duplicate.
      return FALSE;
   }

      // Send ACK flood
   void sendFloodAck(uint16_t dest_node, uint16_t seq_num) {
      pack ackMsg;
      //note that dest_node is originalSrc from the data flood, so the ACK goes to the original sender.
      nx_uint16_t originalSrc;
      //we also need a NEW originalSrc so that the original sender knows who gave it an ACK.
      
      dbg(FLOODING_CHANNEL,"Node %d sending ACK for seq %d to node %d\n", 
          TOS_NODE_ID, seq_num, dest_node);
      
      // Create ACK flooding header
      ackMsg.src = TOS_NODE_ID;
      originalSrc = TOS_NODE_ID;
      ackMsg.dest = dest_node;
      ackMsg.seq = seq_num;
      ackMsg.TTL = MAX_TTL;
      ackMsg.protocol = PROTOCOL_PINGREPLY;//we're replying to a PING, so we can use PINGREPLY.
      
      // embed originalSrc in the payload
      memcpy(ackMsg.payload, &originalSrc, sizeof(nx_uint16_t));
      
      // Send ACK flood via broadcast to start the flood. no need to be more intelligent about who we send to, it's a new flood.
//      forwardFloodToNeighbors(&ackMsg, TOS_NODE_ID); //We could also do it this way, but this function would be doing some duplicate work for no real benefit.
      call Sender.send(ackMsg, AM_BROADCAST_ADDR);
      dbg(FLOODING_CHANNEL,"Node %d sent ACK flood for seq %d\n", TOS_NODE_ID, seq_num);
   }

   event void CommandHandler.ping(uint16_t destAddr, uint8_t *payld){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destAddr, 0, 0, 0, payld, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, destAddr);
   }

   event void CommandHandler.neighDisc(){
   }

   event void CommandHandler.printNeighbors(){
      dbg(GENERAL_CHANNEL, "Node %d: Received printNeighbors command\n", TOS_NODE_ID);
      call NeighborDiscovery.printNeighbors();
   }
// Putting the dbgs from these into the general_channel, so even if we decided to stop tracking the floods and
// neighbors, we can still tell when these operations are meant to *start.*
   event void CommandHandler.startFlood(uint16_t destAddr, uint8_t *payld, uint8_t payldLen){
      dbg(GENERAL_CHANNEL, "Node %d: Received flood command\n", TOS_NODE_ID);
      call Flooding.startFlood(destAddr, payld, payldLen);
   }

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   event void Flooding.floodReceived(uint16_t floodSource, uint16_t seqNum, uint8_t *payld, uint8_t payldLen) {
      dbg(GENERAL_CHANNEL, "Node %d: Received flood from node %d, seq %d, payload: %.*s\n", 
          TOS_NODE_ID, floodSource, seqNum, payldLen, payld);
   }
// Same as above here, we don't need to follow every single operation of flooding, but we can tell when a packet reaches
// its ultimate destination.
   event void Flooding.floodAckReceived(uint16_t source, uint16_t seq) {
      //get the original source out of the payload, so we know who sent our ACK.
//      nx_uint16_t originalSrc;
//      memcpy(&originalSrc, receivedPkt->payload, sizeof(nx_uint16_t));
      dbg(GENERAL_CHANNEL, "Node %d: Received ACK from node %d for flood seq %d\n", 
         TOS_NODE_ID, source, seq);
      
   }

   void makePack(pack *pkg, uint16_t srcAddr, uint16_t destAddr, uint16_t timeToLive, uint16_t prot, uint16_t seqNum, uint8_t* payld, uint8_t payldLen){
      pkg->src = srcAddr;
      pkg->dest = destAddr;
      pkg->TTL = timeToLive;
      pkg->seq = seqNum;
      pkg->protocol = prot;
      memcpy(pkg->payload, payld, payldLen);
   }
}