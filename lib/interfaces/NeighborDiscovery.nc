#include "../../includes/packet.h"

interface NeighborDiscovery{
    command void findNeighbors();
    command void printNeighbors();
    command void neighborUpdate();
}