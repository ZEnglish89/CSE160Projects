#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"

module FloodingP{
    provides interface Flooding;
}

implementation{
    command error_t Flooding.start(){
        dbg(FLOODING_CHANNEL,"This is a flooding test.\n");
    }
}