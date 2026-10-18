// Small 32-bit Windows Winsock check, run through the same Wine/FEX runtime.
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    WSADATA data;
    if (argc != 3 || WSAStartup(MAKEWORD(2, 2), &data)) return 1;
    struct addrinfo *resolved = NULL;
    if (getaddrinfo("localhost", NULL, NULL, &resolved)) return 2;
    freeaddrinfo(resolved);
    const char payload[] = "NTSD-arm64-network";
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    char buffer[128] = {0};
    for (int udp = 0; udp != 2; ++udp) {
        SOCKET sock = socket(AF_INET, udp ? SOCK_DGRAM : SOCK_STREAM, 0);
        DWORD timeout = 10000;
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof timeout);
        address.sin_port = htons((unsigned short)atoi(argv[udp + 1]));
        if (connect(sock, (struct sockaddr *)&address, sizeof address)) return 3;
        if (send(sock, payload, sizeof payload, 0) != sizeof payload) return 4;
        int received = recv(sock, buffer, sizeof buffer, 0);
        if (received != sizeof payload || memcmp(buffer, payload, sizeof payload)) return 5;
        closesocket(sock);
    }
    SOCKET server = socket(AF_INET, SOCK_STREAM, 0);
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = 0;
    if (bind(server, (struct sockaddr *)&address, sizeof address) || listen(server, 1)) return 6;
    int length = sizeof address;
    if (getsockname(server, (struct sockaddr *)&address, &length)) return 7;
    printf("LISTEN_PORT=%u\n", ntohs(address.sin_port));
    fflush(stdout);
    SOCKET peer = accept(server, NULL, NULL);
    int received = recv(peer, buffer, sizeof buffer, 0);
    if (received <= 0 || send(peer, buffer, received, 0) != received) return 8;
    closesocket(peer);
    closesocket(server);
    WSACleanup();
    puts("DNS + outbound TCP/UDP + inbound TCP passed");
    return 0;
}
