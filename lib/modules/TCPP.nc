#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"
#include "../../includes/IP.h"
#include "../../includes/TCP.h"
#include "../../includes/socket.h"
#include <Timer.h>

module TCPP {
    provides interface TCP;
    uses interface IP;
    uses interface Timer<TMilli> as RetransmitTimer;
    uses interface NeighborDiscovery;  // ADDED
}

implementation {
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    uint8_t i;
    uint32_t nextGlobalSequence = 1000; // Start with non-zero sequence
    
    // Structure for unacknowledged segments
    typedef struct {
        uint32_t seqNum;
        uint16_t length;
        uint8_t data[PACKET_MAX_PAYLOAD_SIZE];
        uint32_t timeout;
        uint32_t sendTime;
        socket_t sockId;
        bool isSYN;
        bool isFIN;
    } UnackedSegment;
    
    UnackedSegment unackedQueue[10];
    uint8_t unackedCount = 0;
    bool timerRunning = FALSE;

    // Helper function to get next sequence number
    uint32_t getNextSequence() {
        uint32_t seq = nextGlobalSequence;
        nextGlobalSequence += 1024; // Increment by typical MSS
        return seq;
    }

    // Helper function to find a socket
    socket_store_t* findSocket(uint16_t srcPort, uint16_t destAddr, uint16_t destPort) {
        uint8_t j;
        for(j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
            if(sockets[j].state != CLOSED && 
               sockets[j].src == srcPort && 
               sockets[j].dest.addr == destAddr && 
               sockets[j].dest.port == destPort) {
                return &sockets[j];
            }
        }
        return NULL;
    }

    // Helper function to find a listening socket
    socket_store_t* findListeningSocket(uint16_t port) {
        uint8_t j;
        for(j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
            if(sockets[j].state == LISTEN && sockets[j].src == port) {
                return &sockets[j];
            }
        }
        return NULL;
    }

    // Helper function to get a free socket
    socket_store_t* getFreeSocket() {
        uint8_t j;
        for(j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
            if(sockets[j].state == CLOSED) {
                return &sockets[j];
            }
        }
        return NULL;
    }

    // Helper function for circular buffer acknowledgment checking
    bool isAcknowledged(uint32_t seqNum, uint32_t ackNum) {
        // Simple acknowledgment check - ackNum acknowledges all bytes < ackNum
        return seqNum < ackNum;
    }

    // Helper function to get minimum of two values
    uint32_t min(uint32_t a, uint32_t b) {
        return (a < b) ? a : b;
    }

    // Add segment to retransmission queue
    void addToUnackedQueue(uint32_t seqNum, uint16_t length, uint8_t* data, 
                          socket_t sockId, bool isSYN, bool isFIN) {
        if(unackedCount < 10) {
            unackedQueue[unackedCount].seqNum = seqNum;
            unackedQueue[unackedCount].length = length;
            if(length > 0 && data != NULL) {
                memcpy(unackedQueue[unackedCount].data, data, length);
            }
            unackedQueue[unackedCount].sockId = sockId;
            unackedQueue[unackedCount].timeout = 2000; // 2 second timeout
            unackedQueue[unackedCount].sendTime = 0; // Will be set when timer fires
            unackedQueue[unackedCount].isSYN = isSYN;
            unackedQueue[unackedCount].isFIN = isFIN;
            unackedCount++;
            
            // Start timer if not already running
            if(!timerRunning) {
                call RetransmitTimer.startOneShot(100);
                timerRunning = TRUE;
            }
            
            dbg(TRANSPORT_CHANNEL, "Node %d: Added seq %lu to unacked queue (count: %d)\n",
                TOS_NODE_ID, seqNum, unackedCount);
        }
    }

    // Remove acknowledged segments from queue
    void removeAcknowledged(uint32_t ackNum) {
        uint8_t j = 0;
        for(i = 0; i < unackedCount; i++) {
            if(!isAcknowledged(unackedQueue[i].seqNum, ackNum)) {
                // Keep this segment (not acknowledged yet)
                if(i != j) {
                    memcpy(&unackedQueue[j], &unackedQueue[i], sizeof(UnackedSegment));
                }
                j++;
            } else {
                dbg(TRANSPORT_CHANNEL, "Node %d: Segment seq %lu acknowledged (ack: %lu)\n",
                    TOS_NODE_ID, unackedQueue[i].seqNum, ackNum);
            }
        }
        unackedCount = j;
        
        // Stop timer if no more unacked segments
        if(unackedCount == 0 && timerRunning) {
            call RetransmitTimer.stop();
            timerRunning = FALSE;
        }
    }

    // Send TCP packet
    error_t sendTCPPacket(socket_store_t* sock, TCPHeader* header, 
                         uint8_t* data, uint16_t dataLen, 
                         bool addToQueue, bool isSYN, bool isFIN) {
        uint8_t buffer[PACKET_MAX_PAYLOAD_SIZE];
        uint16_t totalSize;
        socket_t sockId;
        
        totalSize = TCP_HEADER_SIZE + dataLen;
        
        if(totalSize > PACKET_MAX_PAYLOAD_SIZE) {
            dataLen = PACKET_MAX_PAYLOAD_SIZE - TCP_HEADER_SIZE;
            totalSize = TCP_HEADER_SIZE + dataLen;
        }
        
        // Manual packing to avoid alignment issues
        buffer[0] = (header->SrcPort >> 8) & 0xFF;
        buffer[1] = header->SrcPort & 0xFF;
        buffer[2] = (header->DestPort >> 8) & 0xFF;
        buffer[3] = header->DestPort & 0xFF;
        
        buffer[4] = (header->SeqNum >> 24) & 0xFF;
        buffer[5] = (header->SeqNum >> 16) & 0xFF;
        buffer[6] = (header->SeqNum >> 8) & 0xFF;
        buffer[7] = header->SeqNum & 0xFF;
        
        buffer[8] = (header->AckNum >> 24) & 0xFF;
        buffer[9] = (header->AckNum >> 16) & 0xFF;
        buffer[10] = (header->AckNum >> 8) & 0xFF;
        buffer[11] = header->AckNum & 0xFF;
        
        buffer[12] = header->flags;
        buffer[13] = header->reserved;
        
        buffer[14] = (header->AdvWindow >> 8) & 0xFF;
        buffer[15] = header->AdvWindow & 0xFF;
        
        buffer[16] = (header->UrgPtr >> 8) & 0xFF;
        buffer[17] = header->UrgPtr & 0xFF;
        
        if(dataLen > 0 && data != NULL) {
            memcpy(buffer + TCP_HEADER_SIZE, data, dataLen);
        }
        
        // Calculate socket ID
        sockId = (socket_t)(sock - sockets);
        
        // Add debug for sending
        dbg("Project3TGen", "Debug(1): TCP Packet Sent to Node %d for Port %hu (flags: 0x%02x, Seq: %lu, Ack: %lu)\n",
            sock->dest.addr, sock->dest.port, header->flags, 
            header->SeqNum, header->AckNum);
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Sending TCP packet to %d:%hu, flags: 0x%02x, Seq: %lu, Ack: %lu, Win: %hu\n",
            TOS_NODE_ID, sock->dest.addr, sock->dest.port, header->flags, 
            header->SeqNum, header->AckNum, header->AdvWindow);
        
        // For SYN packets, check if we should use flooding
        if(isSYN) {
            // Check if destination is a direct neighbor
            uint8_t neighborCount = call NeighborDiscovery.getNeighborCount();
            uint8_t j;
            bool isNeighbor = FALSE;
            for(j = 0; j < neighborCount; j++) {
                if(call NeighborDiscovery.getNeighbor(j) == sock->dest.addr) {
                    isNeighbor = TRUE;
                    break;
                }
            }
            
            if(!isNeighbor) {
                dbg(TRANSPORT_CHANNEL, "Node %d: Destination %d is not a direct neighbor, TCP may fail\n",
                    TOS_NODE_ID, sock->dest.addr);
            }
        }
        
        // Use IP layer to send
        call IP.sendMessage(sock->dest.addr, buffer, PROTOCOL_TCP);
        
        // Add to retransmission queue if needed
        if(addToQueue) {
            addToUnackedQueue(header->SeqNum, dataLen, data, sockId, isSYN, isFIN);

            // Increment sequence number based on what we just sent
            // SYN and FIN each consume 1 byte, data packets consume their byte count
            if(isSYN) {
                sock->nextSequence++;
            }
            if(isFIN) {
                sock->nextSequence++;
            }
            if(dataLen > 0) {
                sock->nextSequence += dataLen;
            }
        }
        
        return SUCCESS;
    }

    // Handle SYN packet (new connection)
    error_t handleSYN(TCPHeader* header, uint16_t srcAddr) {
        socket_store_t* listenSock;
        socket_store_t* newSock;
        TCPHeader synAckHeader;
        
        // Find listening socket on this port
        listenSock = findListeningSocket(header->DestPort);
        if(listenSock == NULL) {
            dbg(TRANSPORT_CHANNEL, "Node %d: No socket listening on port %hu\n",
                TOS_NODE_ID, header->DestPort);
            return FAIL;
        }
        
        // Get free socket for new connection
        newSock = getFreeSocket();
        if(newSock == NULL) {
            dbg(TRANSPORT_CHANNEL, "Node %d: No free sockets for new connection\n", TOS_NODE_ID);
            return FAIL;
        }
        
        // Initialize new socket for incoming connection
        newSock->state = SYN_RCVD;
        newSock->src = header->DestPort;
        newSock->dest.addr = srcAddr;
        newSock->dest.port = header->SrcPort;
        newSock->nextExpected = header->SeqNum + 1;  // SYN consumes 1 byte
        newSock->nextSequence = getNextSequence();
        newSock->lastByteRead = 0;
        newSock->lastByteRcvd = 0;
        newSock->lastByteAcked = 0;
        newSock->lastByteSent = 0;
        newSock->peerWindow = header->AdvWindow;
        newSock->effectiveWindow = SOCKET_BUFFER_SIZE;
        newSock->RTT = 1000;
        newSock->RTTVar = 0;
        newSock->timeout = 2000;
        newSock->timeWaitCount = 0;
        
        dbg("Project3TGen", "Debug(1): Syn Packet Arrived from Node %d for Port %hu\n",
            srcAddr, header->DestPort);
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Received SYN from %d:%hu, creating socket in SYN_RCVD (expected: %lu)\n",
            TOS_NODE_ID, srcAddr, header->SrcPort, newSock->nextExpected);
        
        // Send SYN-ACK
        synAckHeader.SrcPort = newSock->src;
        synAckHeader.DestPort = newSock->dest.port;
        synAckHeader.SeqNum = newSock->nextSequence;
        synAckHeader.AckNum = newSock->nextExpected;
        synAckHeader.flags = TCP_FLAG_SYN | TCP_FLAG_ACK;
        synAckHeader.reserved = 0;
        synAckHeader.AdvWindow = newSock->effectiveWindow;
        synAckHeader.UrgPtr = 0;
        
        sendTCPPacket(newSock, &synAckHeader, NULL, 0, TRUE, TRUE, FALSE);
        
        // Update lastByteSent to reflect the SYN-ACK we just sent
        newSock->lastByteSent = newSock->nextSequence;
        
        dbg("Project3TGen", "Debug(1): Syn Ack Packet Sent to Node %d for Port %hu\n",
            newSock->dest.addr, newSock->dest.port);
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Sent SYN-ACK to %d:%hu (Seq: %lu, Ack: %lu)\n",
            TOS_NODE_ID, newSock->dest.addr, newSock->dest.port, 
            synAckHeader.SeqNum, synAckHeader.AckNum);
        
        return SUCCESS;
    }

    // Handle established connection packet
    error_t handleEstablishedConnection(socket_store_t* sock, TCPHeader* header, 
                                       uint8_t* data, uint16_t dataLen) {
        TCPHeader ackHeader;
        socket_t sockId = (socket_t)(sock - sockets);
        uint16_t copyLen;
        uint32_t bufferAvailable;
        bool sendAck = FALSE;
        
        // Always update peer window from incoming packet
        sock->peerWindow = header->AdvWindow;
        
        // Process ACK flag
        if(header->flags & TCP_FLAG_ACK) {
            removeAcknowledged(header->AckNum);
            if(header->AckNum > sock->lastByteAcked) {
                sock->lastByteAcked = header->AckNum;
            }
        }
        if(header->flags){
            // Process SYN+ACK (for SYN_SENT state completing handshake)
            if((TCP_FLAG_SYN) && (TCP_FLAG_ACK)) {
                if(sock->state == SYN_SENT && header->AckNum == sock->nextSequence) {
                    sock->nextExpected = header->SeqNum + 1;
                    sock->state = ESTABLISHED;
                    dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d SYN-ACK received, transitioning to ESTABLISHED\n",
                        TOS_NODE_ID, sockId);
                    sendAck = TRUE;
                }
            }
            // Process FIN flag
            else if(TCP_FLAG_FIN) {
                sock->nextExpected = header->SeqNum + 1;
                
                if(sock->state == ESTABLISHED) {
                    sock->state = CLOSE_WAIT;
                    dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d FIN received in ESTABLISHED, moving to CLOSE_WAIT\n",
                        TOS_NODE_ID, sockId);
                } else if(sock->state == FIN_WAIT_1) {
                    sock->state = CLOSING;
                    dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d FIN received in FIN_WAIT_1, moving to CLOSING\n",
                        TOS_NODE_ID, sockId);
                } else if(sock->state == FIN_WAIT_2) {
                    sock->state = TIME_WAIT;
                    sock->timeWaitCount = 100;
                    dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d FIN received in FIN_WAIT_2, moving to TIME_WAIT\n",
                        TOS_NODE_ID, sockId);
                }
                
                sendAck = TRUE;
            }
        }
        // Process data
        else if(dataLen > 0) {
            if(header->SeqNum == sock->nextExpected) {
                // In-order data: copy to receive buffer
                copyLen = dataLen;
                bufferAvailable = SOCKET_BUFFER_SIZE - (sock->lastByteRcvd - sock->lastByteRead);
                if(copyLen > bufferAvailable) {
                    copyLen = bufferAvailable;
                }
                
                if(copyLen > 0) {
                    memcpy(sock->rcvdBuff + (sock->lastByteRcvd % SOCKET_BUFFER_SIZE), data, copyLen);
                    sock->lastByteRcvd += copyLen;
                    sock->nextExpected += copyLen;
                    dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d received %d bytes (Seq: %lu, NextExpected now: %lu)\n",
                        TOS_NODE_ID, sockId, copyLen, header->SeqNum, sock->nextExpected);
                }
                
                sendAck = TRUE;
            } else {
                // Out-of-order data
                dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d out-of-order data (Seq: %lu, expected: %lu)\n",
                    TOS_NODE_ID, sockId, header->SeqNum, sock->nextExpected);
            }
        }
        // Process plain ACK (no data, no SYN, no FIN)
        else if(header->flags & TCP_FLAG_ACK) {
            // Plain ACK already handled above
            if(sock->state == SYN_RCVD) {
                sock->state = ESTABLISHED;
                dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d SYN_RCVD ACK received, transitioning to ESTABLISHED\n",
                    TOS_NODE_ID, sockId);
            } else if(sock->state == FIN_WAIT_1) {
                sock->state = FIN_WAIT_2;
                dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d FIN_WAIT_1 ACK received, moving to FIN_WAIT_2\n",
                    TOS_NODE_ID, sockId);
            } else if(sock->state == CLOSING) {
                sock->state = TIME_WAIT;
                sock->timeWaitCount = 100;
                dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d CLOSING ACK received, moving to TIME_WAIT\n",
                    TOS_NODE_ID, sockId);
            } else if(sock->state == LAST_ACK) {
                sock->state = CLOSED;
                dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d LAST_ACK ACK received, moving to CLOSED\n",
                    TOS_NODE_ID, sockId);
            }
        }
        
        // Send ACK if needed
        if(sendAck) {
            ackHeader.SrcPort = sock->src;
            ackHeader.DestPort = sock->dest.port;
            ackHeader.SeqNum = sock->nextSequence;
            ackHeader.AckNum = sock->nextExpected;
            ackHeader.flags = TCP_FLAG_ACK;
            ackHeader.reserved = 0;
            ackHeader.AdvWindow = SOCKET_BUFFER_SIZE - (sock->lastByteRcvd - sock->lastByteRead);
            ackHeader.UrgPtr = 0;
            
            sendTCPPacket(sock, &ackHeader, NULL, 0, FALSE, FALSE, FALSE);
            
            dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d sent ACK (AckNum: %lu)\n",
                TOS_NODE_ID, sockId, ackHeader.AckNum);
        }
        
        return SUCCESS;
    }

    // Send data with sliding window
    uint16_t sendWithSlidingWindow(socket_store_t* sock, uint8_t* data, uint16_t dataLen) {
        TCPHeader header;
        uint16_t sent = 0;
        uint32_t windowSize;
        uint32_t windowUsed;
        uint32_t windowAvailable;
        socket_t sockId;
        uint16_t maxSegment;
        uint16_t sendSize;
        
        sockId = (socket_t)(sock - sockets);
        
        // Calculate available window
        windowSize = min(sock->peerWindow, sock->effectiveWindow);
        windowUsed = sock->lastByteSent - sock->lastByteAcked;
        windowAvailable = windowSize - windowUsed;
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d window: used=%lu, avail=%lu, peerWin=%lu, effWin=%lu\n",
            TOS_NODE_ID, sockId, windowUsed, windowAvailable, sock->peerWindow, sock->effectiveWindow);
        
        while(sent < dataLen && windowAvailable > 0) {
            sendSize = dataLen - sent;
            if(sendSize > windowAvailable) {
                sendSize = windowAvailable;
            }
            
            // Limit to maximum segment size
            maxSegment = PACKET_MAX_PAYLOAD_SIZE - TCP_HEADER_SIZE;
            if(sendSize > maxSegment) {
                sendSize = maxSegment;
            }
            
            // Prepare header
            header.SrcPort = sock->src;
            header.DestPort = sock->dest.port;
            header.SeqNum = sock->nextSequence;
            header.AckNum = sock->nextExpected;
            header.flags = TCP_FLAG_PUSH | TCP_FLAG_ACK;
            header.reserved = 0;
            header.AdvWindow = SOCKET_BUFFER_SIZE - (sock->lastByteRcvd - sock->lastByteRead);
            header.UrgPtr = 0;
            
            // Send segment
            sendTCPPacket(sock, &header, data + sent, sendSize, TRUE, FALSE, FALSE);
            
            // Update state
            sock->lastByteSent = sock->nextSequence;
            sent += sendSize;
            windowAvailable -= sendSize;
            
            dbg(TRANSPORT_CHANNEL, "Node %d: Sent %d bytes on socket %d (seq: %lu, total sent: %d)\n",
                TOS_NODE_ID, sendSize, sockId, header.SeqNum, sent);
        }
        
        return sent;
    }

    // ========== TCP INTERFACE COMMANDS ==========

    command socket_t TCP.socket() {
        socket_store_t* sock;
        socket_t sockId;
        
        sock = getFreeSocket();
        if(sock != NULL) {
            // Initialize socket
            memset(sock, 0, sizeof(socket_store_t));
            sock->state = CLOSED;
            sock->nextSequence = getNextSequence();
            sock->nextExpected = 0;
            sock->lastByteAcked = 0;
            sock->lastByteSent = 0;
            sock->lastByteRead = 0;
            sock->lastByteRcvd = 0;
            sock->effectiveWindow = SOCKET_BUFFER_SIZE;
            sock->RTT = 1000;
            sock->timeout = 2000;
            sock->timeWaitCount = 0;
            
            sockId = (socket_t)(sock - sockets);
            
            dbg(TRANSPORT_CHANNEL, "Node %d: Created new socket %d (initial seq: %lu)\n",
                TOS_NODE_ID, sockId, sock->nextSequence);
            
            return sockId;
        }
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Failed to create socket - no free sockets\n",
            TOS_NODE_ID);
        return NULL_SOCKET;
    }

    command error_t TCP.bind(socket_t fd, socket_addr_t *addr) {
        socket_store_t* sock;
        
        if(fd >= MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Node %d: bind failed - invalid fd %d\n",
                TOS_NODE_ID, fd);
            return FAIL;
        }
        
        sock = &sockets[fd];
        if(sock->state != CLOSED) {
            dbg(TRANSPORT_CHANNEL, "Node %d: bind failed - socket %d not CLOSED\n",
                TOS_NODE_ID, fd);
            return FAIL;
        }
        
        sock->src = addr->port;
        dbg(TRANSPORT_CHANNEL, "Node %d: Bound socket %d to port %hu\n",
            TOS_NODE_ID, fd, addr->port);
        
        return SUCCESS;
    }

    command error_t TCP.listen(socket_t fd) {
        socket_store_t* sock;
        
        if(fd >= MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Node %d: listen failed - invalid fd %d\n",
                TOS_NODE_ID, fd);
            return FAIL;
        }
        
        sock = &sockets[fd];
        if(sock->state != CLOSED) {
            dbg(TRANSPORT_CHANNEL, "Node %d: listen failed - socket %d not CLOSED\n",
                TOS_NODE_ID, fd);
            return FAIL;
        }
        
        sock->state = LISTEN;
        dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d listening on port %hu\n",
            TOS_NODE_ID, fd, sock->src);
        
        return SUCCESS;
    }

    command error_t TCP.connect(socket_t fd, socket_addr_t *addr) {
        socket_store_t* sock;
        TCPHeader synHeader;
        
        if(fd >= MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Node %d: connect failed - invalid fd %d\n",
                TOS_NODE_ID, fd);
            return FAIL;
        }
        
        sock = &sockets[fd];
        if(sock->state != CLOSED) {
            dbg(TRANSPORT_CHANNEL, "Node %d: connect failed - socket %d not CLOSED\n",
                TOS_NODE_ID, fd);
            return FAIL;
        }
        
        // Initialize connection state
        sock->state = SYN_SENT;
        sock->dest = *addr;
        sock->nextExpected = 0;
        sock->lastByteAcked = 0;
        sock->lastByteSent = 0;
        sock->effectiveWindow = SOCKET_BUFFER_SIZE;
        sock->peerWindow = SOCKET_BUFFER_SIZE;
        
        // Create SYN packet
        synHeader.SrcPort = sock->src;
        synHeader.DestPort = sock->dest.port;
        synHeader.SeqNum = sock->nextSequence;
        synHeader.AckNum = 0;
        synHeader.flags = TCP_FLAG_SYN;
        synHeader.reserved = 0;
        synHeader.AdvWindow = sock->effectiveWindow;
        synHeader.UrgPtr = 0;
        
        // Send SYN
        sendTCPPacket(sock, &synHeader, NULL, 0, TRUE, TRUE, FALSE);
        
        // Update lastByteSent to reflect the SYN we just sent
        sock->lastByteSent = sock->nextSequence;
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d connecting from port %hu to %d:%hu (Seq: %lu)\n",
            TOS_NODE_ID, fd, synHeader.SrcPort, addr->addr, addr->port, synHeader.SeqNum);
        
        return SUCCESS;
    }

    command socket_t TCP.accept(socket_t fd) {
        socket_store_t* listenSock;
        uint8_t j;
        
        if(fd >= MAX_NUM_OF_SOCKETS) {
            return NULL_SOCKET;
        }
        
        listenSock = &sockets[fd];
        if(listenSock->state != LISTEN) {
            return NULL_SOCKET;
        }
        
        // Look for established connections
        for(j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
            if(sockets[j].state == ESTABLISHED && sockets[j].src == listenSock->src) {
                dbg(TRANSPORT_CHANNEL, "Node %d: Accepted connection on socket %d\n", 
                    TOS_NODE_ID, j);
                return j;
            }
        }
        
        return NULL_SOCKET;
    }

    command uint16_t TCP.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        socket_store_t* sock;
        uint16_t copyLen;
        uint32_t bufferAvailable;
        uint16_t sent;
        
        if(fd >= MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Node %d: write failed - invalid fd %d\n",
                TOS_NODE_ID, fd);
            return 0;
        }
        
        sock = &sockets[fd];
        if(sock->state != ESTABLISHED) {
            dbg(TRANSPORT_CHANNEL, "Node %d: write failed - socket %d not ESTABLISHED (state: %d)\n",
                TOS_NODE_ID, fd, sock->state);
            return 0;
        }
        
        // Copy data to send buffer
        copyLen = bufflen;
        bufferAvailable = SOCKET_BUFFER_SIZE - (sock->lastByteSent - sock->lastByteAcked);
        
        if(copyLen > bufferAvailable) {
            copyLen = bufferAvailable;
        }
        
        if(copyLen > 0) {
            memcpy(sock->sendBuffer + (sock->lastByteSent % SOCKET_BUFFER_SIZE), buff, copyLen);
            
            // Send using sliding window
            sent = sendWithSlidingWindow(sock, buff, copyLen);
            
            dbg(TRANSPORT_CHANNEL, "Node %d: Write %d bytes on socket %d (actually sent: %d)\n",
                TOS_NODE_ID, copyLen, fd, sent);
            
            return sent;
        }
        
        return 0;
    }

    command uint16_t TCP.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        socket_store_t* sock;
        uint32_t available;
        uint16_t readLen;
        uint32_t startIdx;
        uint16_t firstPart;
        
        if(fd >= MAX_NUM_OF_SOCKETS) {
            return 0;
        }
        
        sock = &sockets[fd];
        available = sock->lastByteRcvd - sock->lastByteRead;
        
        if(available == 0) {
            return 0;
        }
        
        readLen = bufflen;
        if(readLen > available) {
            readLen = available;
        }
        
        // Copy from circular buffer
        startIdx = sock->lastByteRead % SOCKET_BUFFER_SIZE;
        
        if(startIdx + readLen <= SOCKET_BUFFER_SIZE) {
            // Simple case: no wrap-around
            memcpy(buff, sock->rcvdBuff + startIdx, readLen);
        } else {
            // Wrap-around case
            firstPart = SOCKET_BUFFER_SIZE - startIdx;
            memcpy(buff, sock->rcvdBuff + startIdx, firstPart);
            memcpy(buff + firstPart, sock->rcvdBuff, readLen - firstPart);
        }
        
        sock->lastByteRead += readLen;
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Read %d bytes from socket %d (available: %lu)\n",
            TOS_NODE_ID, readLen, fd, available);
        
        // Log the data for project requirements
        if(readLen > 0) {
            dbg("Project3TGen", "Node %d: Read Data from socket %d: %.*s\n",
                TOS_NODE_ID, fd, readLen, buff);
        }
        
        return readLen;
    }

    command error_t TCP.close(socket_t fd) {
        socket_store_t* sock;
        TCPHeader finHeader;
        
        if(fd >= MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Node %d: close failed - invalid fd %d\n",
                TOS_NODE_ID, fd);
            return FAIL;
        }
        
        sock = &sockets[fd];
        
        if(sock->state == ESTABLISHED) {
            // Send FIN packet
            finHeader.SrcPort = sock->src;
            finHeader.DestPort = sock->dest.port;
            finHeader.SeqNum = sock->nextSequence;
            finHeader.AckNum = sock->nextExpected;
            finHeader.flags = TCP_FLAG_FIN | TCP_FLAG_ACK;
            finHeader.reserved = 0;
            finHeader.AdvWindow = sock->effectiveWindow;
            finHeader.UrgPtr = 0;
            
            sendTCPPacket(sock, &finHeader, NULL, 0, TRUE, FALSE, TRUE);
            
            sock->state = FIN_WAIT_1;
            
            dbg(TRANSPORT_CHANNEL, "Node %d: Sent FIN on socket %d, moving to FIN_WAIT_1\n",
                TOS_NODE_ID, fd);
        } else if(sock->state == CLOSE_WAIT) {
            // Send FIN for passive close
            finHeader.SrcPort = sock->src;
            finHeader.DestPort = sock->dest.port;
            finHeader.SeqNum = sock->nextSequence;
            finHeader.AckNum = sock->nextExpected;
            finHeader.flags = TCP_FLAG_FIN | TCP_FLAG_ACK;
            finHeader.reserved = 0;
            finHeader.AdvWindow = sock->effectiveWindow;
            finHeader.UrgPtr = 0;
            
            sendTCPPacket(sock, &finHeader, NULL, 0, TRUE, FALSE, TRUE);
            
            sock->state = LAST_ACK;
            
            dbg(TRANSPORT_CHANNEL, "Node %d: Sent FIN on socket %d, moving to LAST_ACK\n",
                TOS_NODE_ID, fd);
        } else {
            // Just close the socket
            sock->state = CLOSED;
            dbg(TRANSPORT_CHANNEL, "Node %d: Closed socket %d\n",
                TOS_NODE_ID, fd);
        }
        
        return SUCCESS;
    }

    command error_t TCP.receive(pack* package, uint8_t pktLen) {
        TCPHeader header;
        uint16_t dataLen;
        socket_store_t* sock;
        uint8_t* payload;
        uint16_t srcAddr;
        TCPHeader ackHeader;
        
        if(package == NULL) {
            return FAIL;
        }
        
        // Extract TCP header from payload (after IP header)
        payload = (uint8_t*)package->payload + IP_HEADER_SIZE;
        srcAddr = package->src;
        
        // Manual copy of TCP header
        header.SrcPort = (payload[0] << 8) | payload[1];
        header.DestPort = (payload[2] << 8) | payload[3];
        header.SeqNum = ((uint32_t)payload[4] << 24) | 
                    ((uint32_t)payload[5] << 16) | 
                    ((uint32_t)payload[6] << 8) | 
                    payload[7];
        header.AckNum = ((uint32_t)payload[8] << 24) | 
                    ((uint32_t)payload[9] << 16) | 
                    ((uint32_t)payload[10] << 8) | 
                    payload[11];
        header.flags = payload[12];
        header.reserved = payload[13];
        header.AdvWindow = (payload[14] << 8) | payload[15];
        header.UrgPtr = (payload[16] << 8) | payload[17];
        
        // Calculate data length from actual packet length
        if (pktLen > (uint8_t)(IP_HEADER_SIZE + TCP_HEADER_SIZE)) {
            dataLen = pktLen - IP_HEADER_SIZE - TCP_HEADER_SIZE;
        } else {
            dataLen = 0;
        }
        
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Received TCP packet from %d:%hu to port %hu, flags: 0x%02x, Seq: %lu, Ack: %lu\n",
            TOS_NODE_ID, srcAddr, header.SrcPort, header.DestPort, 
            header.flags, header.SeqNum, header.AckNum);
        
        // Find existing socket
        sock = findSocket(header.DestPort, srcAddr, header.SrcPort);
        
        if(sock == NULL) {
            // Handle new connection (SYN packet)
            if((header.flags & TCP_FLAG_SYN) && !(header.flags & TCP_FLAG_ACK)) {
                return handleSYN(&header, srcAddr);
            }
            
            dbg(TRANSPORT_CHANNEL, "Node %d: No socket found for packet from %d:%hu\n",
                TOS_NODE_ID, srcAddr, header.SrcPort);
            return FAIL;
        }
        
        // Handle based on socket state
        switch(sock->state) {
            case SYN_SENT:
            case SYN_RCVD:
            case ESTABLISHED:
            case FIN_WAIT_1:
            case FIN_WAIT_2:
            case CLOSING:
            case CLOSE_WAIT:
            case LAST_ACK:
                            // Handle SYN-ACK for our connection attempt
                if((header.flags & TCP_FLAG_SYN) && (header.flags & TCP_FLAG_ACK)) {
                    if(header.AckNum == sock->nextSequence) {
                        removeAcknowledged(header.AckNum);
                        sock->nextExpected = header.SeqNum + 1;  // SYN consumes 1 byte
                        sock->state = ESTABLISHED;
                        sock->peerWindow = header.AdvWindow;
                        
                        // Send ACK
                        ackHeader.SrcPort = sock->src;
                        ackHeader.DestPort = sock->dest.port;
                        ackHeader.SeqNum = sock->nextSequence;
                        ackHeader.AckNum = sock->nextExpected;
                        ackHeader.flags = TCP_FLAG_ACK;
                        ackHeader.reserved = 0;
                        ackHeader.AdvWindow = sock->effectiveWindow;
                        ackHeader.UrgPtr = 0;
                        
                        sendTCPPacket(sock, &ackHeader, NULL, 0, FALSE, FALSE, FALSE);
                        
                        dbg(TRANSPORT_CHANNEL, "Node %d: Connection ESTABLISHED (socket %d)\n",
                            TOS_NODE_ID, (socket_t)(sock - sockets));
                    }
                }

                else{
                    return handleEstablishedConnection(sock, &header, 
                    payload + TCP_HEADER_SIZE, dataLen);
                }

                break;
            case TIME_WAIT:
                if(sock->timeWaitCount > 0) {
                    sock->timeWaitCount--;
                } else {
                    sock->state = CLOSED;
                }
                break;
                
            default:
                break;
        }
        
        return SUCCESS;
    }
    
    // Retransmission timer event
    event void RetransmitTimer.fired() {
        uint32_t currentTime = 0; // Simplified - would normally get from timer
        uint8_t j;
        
        // Check for timed out segments
        for(j = 0; j < unackedCount; j++) {
            // Simple timeout check (simplified)
            if(unackedQueue[j].timeout > 0) {
                unackedQueue[j].timeout--;
            } else {
                // Retransmit this segment
                socket_store_t* sock = &sockets[unackedQueue[j].sockId];
                TCPHeader retransHeader;
                
                retransHeader.SrcPort = sock->src;
                retransHeader.DestPort = sock->dest.port;
                retransHeader.SeqNum = unackedQueue[j].seqNum;
                retransHeader.AckNum = sock->nextExpected;
                retransHeader.flags = TCP_FLAG_ACK;
                
                if(unackedQueue[j].isSYN) {
                    retransHeader.flags |= TCP_FLAG_SYN;
                }
                if(unackedQueue[j].isFIN) {
                    retransHeader.flags |= TCP_FLAG_FIN;
                }
                if(unackedQueue[j].length > 0) {
                    retransHeader.flags |= TCP_FLAG_PUSH;
                }
                
                retransHeader.reserved = 0;
                retransHeader.AdvWindow = sock->effectiveWindow;
                retransHeader.UrgPtr = 0;
                
                // Retransmit without re-adding to unacked queue and without
                // advancing the sequence (it's already accounted for)
                sendTCPPacket(sock, &retransHeader, 
                            unackedQueue[j].data, unackedQueue[j].length, 
                            FALSE, unackedQueue[j].isSYN, unackedQueue[j].isFIN);
                
                // Reset timeout with exponential backoff
                unackedQueue[j].timeout = 2000; // Reset to 2 seconds
                
                dbg(TRANSPORT_CHANNEL, "Node %d: Retransmitting segment (Seq: %lu) on socket %d\n",
                    TOS_NODE_ID, unackedQueue[j].seqNum, unackedQueue[j].sockId);
            }
        }
        
        // Restart timer if there are still unacked segments
        if(unackedCount > 0) {
            call RetransmitTimer.startOneShot(100); // Check every 100ms
        } else {
            timerRunning = FALSE;
        }
    }
    
    // NeighborDiscovery event implementation
    event void NeighborDiscovery.neighborsChanged(uint8_t neighborCount) {
        // This event is triggered when neighbor table changes
        // We don't need to do anything special for TCP, but we must implement it
        dbg(TRANSPORT_CHANNEL, "Node %d: TCP neighborsChanged event: %d neighbors\n",
            TOS_NODE_ID, neighborCount);
    }
}