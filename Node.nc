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

   void makePack(pack *pkg, uint16_t srcAddr, uint16_t destAddr, uint16_t timeToLive, uint16_t prot, uint16_t seqNum, uint8_t *payld, uint8_t payldLen);

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
               call Flooding.handleFloodPacket(myMsg, len, myMsg->src);
               return msg;
         }
         
      }
      //we shouldn't ever get here, but still.
      dbg(GENERAL_CHANNEL, "Packet Received - Unknown Packet Type %d\n", len);
      return msg;
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