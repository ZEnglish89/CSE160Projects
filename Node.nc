/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

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

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         call NeighborDiscovery.findNeighbors();
         //call NeighborDiscovery.printNeighbors();
         call Flooding.start();
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
         
         // If we get here, it's not a neighbor discovery packet
         dbg(GENERAL_CHANNEL, "Packet Received\n");
         dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         return msg;
      }
      
      dbg(GENERAL_CHANNEL, "Packet Received - Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, destination);
   }

   event void CommandHandler.neighDisc(){
      //void* payload = "XXXXX";
      //dbg(GENERAL_CHANNEL, "NEIGHBOR DISCOVERY EVENT \n");
      //makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      //call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }

   event void CommandHandler.printNeighbors(){
      dbg(GENERAL_CHANNEL, "Node %d: Received printNeighbors command\n", TOS_NODE_ID);
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

//   command void NeighborDiscovery.findNeighbors(){
//      dbg(GENERAL_CHANNEL, "===Finding Neighbors===\n");
//   }

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}
