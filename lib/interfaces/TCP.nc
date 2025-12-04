#include "../../includes/packet.h"
#include "../../includes/socket.h"

interface TCP {
    command socket_t socket();
    command error_t bind(socket_t fd, socket_addr_t *addr);
    command error_t connect(socket_t fd, socket_addr_t *addr);
    command error_t listen(socket_t fd);
    command socket_t accept(socket_t fd);
    command uint16_t write(socket_t fd, uint8_t *buff, uint16_t bufflen);
    command uint16_t read(socket_t fd, uint8_t *buff, uint16_t bufflen);
    command error_t close(socket_t fd);
    command error_t receive(pack* package, uint8_t pktLen, uint16_t srcAddr);
    command uint8_t getState(socket_t fd);
    
}