interface CommandHandler {
    event void ping(uint16_t destination, uint8_t *payload);
    event void neighDisc();
    event void printNeighbors();
    event void printRouteTable();
    event void printLinkState();
    event void printDistanceVector();
    event void setTestServer();
    event void setTestClient();
    event void setAppServer();
    event void setAppClient();
    event void startFlood(uint16_t dest, uint8_t *payload, uint8_t length);
}
