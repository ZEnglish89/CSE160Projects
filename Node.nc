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
#include "../../includes/socket.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   uses interface Flooding;

   uses interface NeighborDiscovery;

   uses interface LinkState;

   uses interface IP;

   uses interface TCP;
   
   uses interface Timer<TMilli> as AppTimer;
}

implementation{
   pack sendPackage;
   
   // Test application variables
   socket_t testServerFd = NULL_SOCKET;
   socket_t testClientFd = NULL_SOCKET;
   uint16_t bytesToTransfer = 0;
   uint16_t currentNumber = 0;
   bool clientConnected = FALSE;
   bool serverReady = FALSE;
   uint8_t acceptedSockets[5];
   uint8_t acceptedCount = 0;
   uint32_t connectAttempts = 0;  // Changed to uint32_t
   uint32_t clientTimer = 0;      // Added for timing

   void makePack(pack *pkg, uint16_t srcAddr, uint16_t destAddr, uint16_t timeToLive, uint16_t prot, uint16_t seqNum, uint8_t *payld, uint8_t payldLen);

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
      
      // Start application timer for periodic checks
      call AppTimer.startPeriodic(1000); // Check every second
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         call NeighborDiscovery.findNeighbors();
         call Flooding.initializeFlooding();
         call LinkState.initializeRouting();
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

		//if this is either a Neighbordiscovery message or a Neighbordiscovery response
		if((strncmp((char*)myMsg->payload, "NEIGHBOR_DISC", 13) == 0)||(strncmp((char*)myMsg->payload, "NEIGHBOR_RESP", 13) == 0)){ 
			//if we're the sender, just completely ignore it and move on.
			if(myMsg->src!=TOS_NODE_ID){
				//let the relevant module handle it.
				call NeighborDiscovery.handleNeighborPacket(myMsg,responseMsg,responsePayload);
			}
			return msg;
		}
/*      // Check if this is a TCP packet
//actually, we don't want to do this because IP needs to handle multi-hop TCP connections. 
        else if(myMsg->protocol == PROTOCOL_TCP) {
            call TCP.receive(myMsg, len);
            return msg;
        }*/
      //otherwise, let the IP module handle it
      else{
         call IP.handleMessage(myMsg,len,myMsg->src);
         return msg;
      }
      }
      //we shouldn't ever get here, but still.
      dbg(GENERAL_CHANNEL, "Packet Received - Unknown Packet Type %d\n", len);
      return msg;
   }

   event void CommandHandler.ping(uint16_t destAddr, uint8_t *payld){
      dbg(GENERAL_CHANNEL, "PING EVENT - Sending to %d\n", destAddr);
      call IP.sendMessage(destAddr,payld,PROTOCOL_PING);
   }

   event void CommandHandler.neighDisc(){
   }

   event void CommandHandler.printNeighbors(){
      dbg(GENERAL_CHANNEL, "Node %d: Received printNeighbors command\n", TOS_NODE_ID);
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.startFlood(uint16_t destAddr, uint8_t *payld, uint8_t payldLen){
      dbg(GENERAL_CHANNEL, "Node %d: Received flood command\n", TOS_NODE_ID);
      call Flooding.startFlood(destAddr, payld, payldLen,PROTOCOL_PING);
   }

   event void CommandHandler.printRouteTable(){
      dbg(GENERAL_CHANNEL, "Node %d: Received printRouteTable command\n", TOS_NODE_ID);
      call LinkState.printRouteTable();
   }

   event void CommandHandler.printLinkState(){
      dbg(GENERAL_CHANNEL, "Node %d: Received printLinkState command\n", TOS_NODE_ID);
      call LinkState.printLinkState();
   }

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){
      dbg(TRANSPORT_CHANNEL, "Node %d: Setting up test server\n", TOS_NODE_ID);
      
      //if the given id isn't already in use, we make a new socket.
      if(testServerFd == NULL_SOCKET) {
          testServerFd = call TCP.socket();
          if(testServerFd != NULL_SOCKET) {
              socket_addr_t addr;
              addr.addr = TOS_NODE_ID;
              addr.port = 123; // Always use port 123 for server, well-known port.
              
              //these will pretty much always return success but it's a useful formality.
              //bind the Server to the port, and have it listen for incoming connections.
              if(call TCP.bind(testServerFd, &addr) == SUCCESS) {
                  if(call TCP.listen(testServerFd) == SUCCESS) {
                      serverReady = TRUE;
                      dbg(TRANSPORT_CHANNEL, "Node %d: Server listening on port 123\n", TOS_NODE_ID);
                  }
              }
          } else {
              dbg(TRANSPORT_CHANNEL, "Node %d: Failed to create server socket\n", TOS_NODE_ID);
          }
      } else {
          dbg(TRANSPORT_CHANNEL, "Node %d: Server already running on socket %d\n", TOS_NODE_ID, testServerFd);
      }
   }

   event void CommandHandler.setTestClient(){
      dbg(TRANSPORT_CHANNEL, "Node %d: Setting up test client\n", TOS_NODE_ID);
      
      // we're using hardcoded values for right now.
      if(testClientFd == NULL_SOCKET) {
          testClientFd = call TCP.socket();
          if(testClientFd != NULL_SOCKET) {
              socket_addr_t localAddr;
              localAddr.addr = TOS_NODE_ID;
              localAddr.port = 456; // Use port 456 for client
              
              if(call TCP.bind(testClientFd, &localAddr) == SUCCESS) {
                  socket_addr_t serverAddr;
                  serverAddr.addr = 1; // Always connect to node 1 as the server.
                  serverAddr.port = 123; // Always connect to port 123, well-known port.
                  
                  bytesToTransfer = 20;
                  currentNumber = 0;
                  clientConnected = FALSE;
                  connectAttempts = 0;
                  clientTimer = 0;
                  
                  //initiated a connection with our new socket.
                  if(call TCP.connect(testClientFd, &serverAddr) == SUCCESS) {
                      dbg(TRANSPORT_CHANNEL, "Node %d: Client connecting to node 1 port 123 from local port %hu\n", 
                          TOS_NODE_ID, localAddr.port);
                  } else {
                      dbg(TRANSPORT_CHANNEL, "Node %d: Client connect failed\n", TOS_NODE_ID);
                  }
              } else {
                  dbg(TRANSPORT_CHANNEL, "Node %d: Client bind failed\n", TOS_NODE_ID);
              }
          } else {
              dbg(TRANSPORT_CHANNEL, "Node %d: Failed to create client socket\n", TOS_NODE_ID);
          }
      } else {
          dbg(TRANSPORT_CHANNEL, "Node %d: Client already running on socket %d\n", TOS_NODE_ID, testClientFd);
      }
   }

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){
      // if the client's socket is active, close it and mark it as such.
      if(testClientFd != NULL_SOCKET) {
         dbg(TRANSPORT_CHANNEL, "Node %d: Closing client socket %d\n", TOS_NODE_ID, testClientFd);
         call TCP.close(testClientFd);
         testClientFd = NULL_SOCKET;
         clientConnected = FALSE;
      }
   }

   event void Flooding.floodReceived(uint16_t floodSource, uint16_t seqNum, uint8_t *payld, uint8_t payldLen) {
   }

   event void Flooding.floodAckReceived(uint16_t source, uint16_t seq) {
   }

   event void NeighborDiscovery.neighborsChanged(uint8_t neighborCount){
      dbg(NEIGHBOR_CHANNEL, "Node %d: neighborsChanged signaled, neighborCount=%d\n", TOS_NODE_ID, neighborCount);
      call LinkState.startRouting();
   }
   
    // Application timer event for periodic tasks
    event void AppTimer.fired() {
        uint8_t i;
        socket_t acceptedFd;
        uint8_t buffer[128];
        uint16_t bytesRead;
        uint8_t numbersToSend;
        uint8_t pos;
        uint16_t number;
        uint16_t sent;
        bool alreadyAccepted;
        uint8_t k;
        bool foundEnd;
        uint8_t j;
        static bool connectionAlreadyAccepted = FALSE;  // Track if we've accepted
        
        // Server: Check for new connections and read data
        if(serverReady && testServerFd != NULL_SOCKET) {
            // Only try to accept once
            if(!connectionAlreadyAccepted) {
                acceptedFd = call TCP.accept(testServerFd);
                //if the connection was accepted and the socket is good, log that socket.
                if(acceptedFd != NULL_SOCKET) {
                    acceptedSockets[0] = acceptedFd;
                    acceptedCount = 1;
                    connectionAlreadyAccepted = TRUE;
                    
                    dbg(PROJECT3TGEN_CHANNEL, "Node %d: Accepted connection on socket %d\n",
                        TOS_NODE_ID, acceptedFd);
                    dbg(TRANSPORT_CHANNEL, "Node %d: Accepted connection on socket %d\n", 
                        TOS_NODE_ID, acceptedFd);
                }
            }
            
            // Only read from sockets that are ESTABLISHED
            if(acceptedCount > 0) {
                for(i = 0; i < acceptedCount; i++) {
                    //this could hypothetically let us detect inactive sockets.
                    static uint8_t consecutiveEmptyReads = 0;
                    
                    bytesRead = call TCP.read(acceptedSockets[i], buffer, sizeof(buffer));
                    
                    if(bytesRead > 0) {
                        //if we read something, we don't have an empty read.
                        consecutiveEmptyReads = 0;  // Reset counter
                        
                        // print what we read, byte by byte.
                        dbg(TRANSPORT_CHANNEL, "Node %d: Reading Data length %d from socket %d:\n", 
                            TOS_NODE_ID, bytesRead, acceptedSockets[i]);

                        for(j=0;j<bytesRead;j++){
                            dbg(TRANSPORT_CHANNEL,"%d\n",buffer[j]);
                        }

                        
                        // Check for complete data set
                        foundEnd = FALSE;
                        if(bytesRead >= 15) {
                            for(j = 0; j <= bytesRead - 15; j++) {
                                if(memcmp(buffer + j, "END_OF_TRANSFER", 15) == 0) {
                                    foundEnd = TRUE;
                                    break;
                                }
                            }
                        }
                        
                        //if we're confident that we've got all the data, we can close up shop.
                        if(foundEnd) {
                            dbg(PROJECT3TGEN_CHANNEL, "Node %d: Complete data set received, closing connection\n",
                                TOS_NODE_ID);
                            call TCP.close(acceptedSockets[i]);
                            // Clear the socket
                            acceptedSockets[i] = NULL_SOCKET;
                            acceptedCount = 0;
                            connectionAlreadyAccepted = FALSE;
                            break;
                        }
                    
                    } 
                    
                    else {
                        consecutiveEmptyReads++;
                        
                        // If we've had many empty reads, the connection might be closing.
                        //we don't do anything with it here, but this does have a use case.
                        if(consecutiveEmptyReads > 10) {
//                            dbg(TRANSPORT_CHANNEL, "Node %d: Many empty reads on socket %d\n",
//                                TOS_NODE_ID, acceptedSockets[i]);
                        }
                        
                    }
                }
            }
        }
        
        // Client: Check connection status and send data
        if(testClientFd != NULL_SOCKET) {
            clientTimer++;
            
            // Connection timeout - check actual socket state
            if(!clientConnected) {
                // Check if socket has actually reached ESTABLISHED state, we can't just assume
                //that connect() worked if we have noise present.
                uint8_t sockState = call TCP.getState(testClientFd);
                
                if(sockState == ESTABLISHED) {
                    // Connection successful!
                    clientConnected = TRUE;
                    connectAttempts = 0;
                    dbg(PROJECT3TGEN_CHANNEL, "Node %d: Client connection ESTABLISHED\n",
                        TOS_NODE_ID);
                } else if(sockState == CLOSED) {
                    // Socket closed unexpectedly
                    dbg(PROJECT3TGEN_CHANNEL, "Node %d: Client socket closed unexpectedly\n",
                        TOS_NODE_ID);
                    testClientFd = NULL_SOCKET;
                    clientConnected = FALSE;
                    connectAttempts = 0;
                    return;
                } else {
                    //if it's not established or closed, it means that it's attempting to open but hasn't been successful.
                    connectAttempts++;
                    
                    //if we check the state several times and it still hasn't converged somewhere, we can timeout and try
                    //to connect again.
                    if(connectAttempts > 5) {
                        dbg(PROJECT3TGEN_CHANNEL, "Node %d: Connection timeout after %d attempts, retrying\n",
                            TOS_NODE_ID, connectAttempts);
                        // Close socket, mark it as closed.
                        call TCP.close(testClientFd);
                        testClientFd = NULL_SOCKET;
                        clientConnected = FALSE;
                        connectAttempts = 0;
                        clientTimer = 0;
                        
                        // Immediately retry: create new socket and connect
                        testClientFd = call TCP.socket();
                        if(testClientFd != NULL_SOCKET) {
                            socket_addr_t localAddr;
                            localAddr.addr = TOS_NODE_ID;
                            localAddr.port = 456; // Use port 456 for client
                            
                            if(call TCP.bind(testClientFd, &localAddr) == SUCCESS) {
                                socket_addr_t serverAddr;
                                serverAddr.addr = 1; // Always connect to node 1
                                serverAddr.port = 123; // Always connect to port 123
                                
                                if(call TCP.connect(testClientFd, &serverAddr) == SUCCESS) {
                                    dbg(TRANSPORT_CHANNEL, "Node %d: Client retrying connection to node 1 port 123\n", 
                                        TOS_NODE_ID);
                                }
                            }
                        }
                        return;
                    }
                }
            }
            
            // Send data if connected
            if(clientConnected && currentNumber < bytesToTransfer) {
                // Send immediately
                numbersToSend = 20;
                pos = 0;
                
                if(currentNumber + numbersToSend > bytesToTransfer) {
                    numbersToSend = bytesToTransfer - currentNumber;
                }
                
                // Create comma-separated list of numbers
                for(i = 0; i < numbersToSend; i++) {
                    number = currentNumber + i;
                    
                    // Simple number
                    if(number < 10) {
                        buffer[pos++] = number;
                    } else {
                        // For simplicity, just send single digit
                        buffer[pos++] = (number % 10);
                    }
                    
                    if(i < numbersToSend - 1) {
                        buffer[pos++] = ',';
                    }
                }
                
                // Add end marker immediately
                if(pos + 15 < sizeof(buffer)) {
                    memcpy(buffer + pos, "END_OF_TRANSFER", 15);
                    pos += 15;
                }
                
                //then write to the outgoing buffer
                sent = call TCP.write(testClientFd, buffer, pos);
                if(sent > 0) {
                    dbg(PROJECT3TGEN_CHANNEL, "Node %d: Sent %d bytes on socket %d\n",
                        TOS_NODE_ID, sent, testClientFd);
                    
                    currentNumber += numbersToSend;
                    
/*                    // Close immediately after sending all data
                    if(currentNumber >= bytesToTransfer) {
                        dbg(PROJECT3TGEN_CHANNEL, "Node %d: All data sent, initiating graceful close\n", 
                            TOS_NODE_ID);
                        
                        // Small delay before close
                        if(clientTimer % 2 == 0) {  // Wait 2 seconds
                            call TCP.close(testClientFd);
                            testClientFd = NULL_SOCKET;
                            clientConnected = FALSE;
                            currentNumber = 0;
                        }
                    }
                    */ //we DONT want to do that because we still have to hang around and wait for potential retransmissions.
                }
            }
        }
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