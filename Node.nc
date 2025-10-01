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
         call NeighborDiscovery.findNeighbors();
         call Flooding.initializeFlooding();
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
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
                  
                  // Add the discoverer to our neighbor table
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
      FloodHeader fh;
      uint8_t appPayloadLength;
      uint8_t appPayloadBuffer[PACKET_MAX_PAYLOAD_SIZE - FLOOD_HEADER_SIZE];
      
      // Copy the flooding header from the packet payload
      memcpy(&fh, receivedPkt->payload, FLOOD_HEADER_SIZE);
      
      dbg(FLOODING_CHANNEL,"Node %d received flood type %d from src %d dest %d seq %d TTL %d via node %d\n", 
          TOS_NODE_ID, fh.floodType, fh.floodSrc, fh.floodDest, fh.floodSeq, fh.floodTTL, senderId);
      
      //Now we have to check all the different reasons why we may want to drop it or treat it special: duplicates, dead TTL, if it's just an ACK, etc.
      // Check for duplicates
      if(isDuplicateFlood(fh.floodSrc, fh.floodSeq)) {
         dbg(FLOODING_CHANNEL,"Node %d dropping duplicate flood\n", TOS_NODE_ID);
         return;
      }
      
      // Check TTL
      if(fh.floodTTL == 0) {
         dbg(FLOODING_CHANNEL,"Node %d dropping flood - TTL expired\n", TOS_NODE_ID);
         return;
      }

      //it could be useful to check the TTL *and* see if it's an ACK or not simultaneously, so we can report what type of flood got dropped.
      //consider for future updates, I suppose.

      // Handle ACK floods
      if(fh.floodType == FLOOD_TYPE_ACK) {
         //If we're the destination, signal that we got it and move on.
         if(fh.floodDest == TOS_NODE_ID) {
//          We announce it in the floodAckReceived() function, so no point in saying it twice.
//            dbg(FLOODING_CHANNEL,"Node %d received ACK for flood seq %d from node %d\n", TOS_NODE_ID, fh.floodSeq, fh.floodSrc);
            signal Flooding.floodAckReceived(fh.floodSrc, fh.floodSeq);
            //The ACK got to us, no reason to keep flooding it.
            return;
         }
         
         //Otherwise, forward it further. No need to check TTL because we did that above.
         // Decrement TTL and update the packet
         fh.floodTTL--;
         memcpy(receivedPkt->payload, &fh, FLOOD_HEADER_SIZE);
         
         //Forward the ACK to everyone except the node who sent it to us, to minimize looping.
         forwardFloodToNeighbors(receivedPkt, senderId);
         dbg(FLOODING_CHANNEL,"Node %d forwarding ACK flood seq %d\n", TOS_NODE_ID, fh.floodSeq);
         return;
      }
      
      // Handle regular/data floods, now that ACKs are out of the way.
      // Check if this flood is targeted(not a broadcast) and we're not the destination
      if(fh.floodDest != 0 && fh.floodDest != TOS_NODE_ID) {
         //If it's targeted but we aren't the destination, then we skip all the hard work and move ahead to forwarding it.
         dbg(FLOODING_CHANNEL,"Node %d forwarding targeted flood (not for us)\n", TOS_NODE_ID);
      } else {
         // We are either the destination or it's a broadcast flood, so we have to actually deal with it.
         // Calculate application payload length
         appPayloadLength = PACKET_MAX_PAYLOAD_SIZE - FLOOD_HEADER_SIZE;
         
         // Copy application payload to buffer, ta-daa it's ours now.
         memcpy(appPayloadBuffer, &receivedPkt->payload[FLOOD_HEADER_SIZE], appPayloadLength);
         
         // Signal application that we received a flood
         signal Flooding.floodReceived(fh.floodSrc, fh.floodSeq, appPayloadBuffer, appPayloadLength);
         
         // If this is a targeted flood and we're the destination, send an ACK in return.
         if(fh.floodDest != 0 && fh.floodDest == TOS_NODE_ID) {
            dbg(FLOODING_CHANNEL,"Node %d is destination for targeted flood seq %d, sending ACK\n", 
                TOS_NODE_ID, fh.floodSeq);
            // Send ACK back to source
            sendFloodAck(fh.floodSrc, fh.floodSeq);
            // The flood has already reached us, so there's no reason to keep forwarding.
            return;
         }
      }
      
      // Decrement TTL and get ready to forward.
      fh.floodTTL--;
      memcpy(receivedPkt->payload, &fh, FLOOD_HEADER_SIZE);
      
      // Forward to everyone except who sent it to us, just like above.
      forwardFloodToNeighbors(receivedPkt, senderId);
   }

   // Forward a flood packet to all the node's neighbors except the one they received it from.
   void forwardFloodToNeighbors(pack* floodPkt, uint16_t senderId) {
      uint8_t i;
      uint8_t neighborCount;
      uint16_t neighborId;
      bool forwarded = FALSE;
      FloodHeader fh;
      
      // Copy flooding header to read sequence number
      memcpy(&fh, floodPkt->payload, FLOOD_HEADER_SIZE);
      
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
                TOS_NODE_ID, fh.floodSeq, neighborId);
            //Then send that bad boy!
            call Sender.send(*floodPkt, neighborId);
            forwarded = TRUE;
         }
      }
      //If we check all of our neighbors and there's nobody to forward it to, then say so and move on.
      if(!forwarded) {
         dbg(FLOODING_CHANNEL,"Node %d has no other neighbors to forward flood seq %d\n", 
             TOS_NODE_ID, fh.floodSeq);
      }
   }

   // Check if we've seen this flood before
   bool isDuplicateFlood(uint16_t floodSource, uint16_t seqNum) {
      uint8_t i;
      for(i = 0; i < floodCacheSize; i++) {
         //if the flood came from the node we're currently considering.
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
      FloodHeader fh;
      
      dbg(FLOODING_CHANNEL,"Node %d sending ACK for seq %d to node %d\n", 
          TOS_NODE_ID, seq_num, dest_node);
      
      // Create ACK flooding header
      fh.floodSrc = TOS_NODE_ID;
      fh.floodDest = dest_node;
      fh.floodSeq = seq_num;
      fh.floodTTL = MAX_TTL;
      fh.floodType = FLOOD_TYPE_ACK;
      
      // Create ACK packet
      ackMsg.src = TOS_NODE_ID;
      ackMsg.dest = AM_BROADCAST_ADDR;
      ackMsg.seq = 0;
      ackMsg.TTL = MAX_TTL;
      //I don't think it actually makes a material difference if this is a ping or a pingreply, but it's thematically accurate.
      ackMsg.protocol = PROTOCOL_PINGREPLY;
      
      // Copy flooding header to payload
      memcpy(ackMsg.payload, &fh, FLOOD_HEADER_SIZE);
      
      // Send ACK flood via broadcast to start the flood. no need to be more intelligent about who we send to, it's a new flood.
      forwardFloodToNeighbors(&ackMsg, TOS_NODE_ID);
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

   event void Flooding.floodAckReceived(uint16_t source, uint16_t seq) {
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