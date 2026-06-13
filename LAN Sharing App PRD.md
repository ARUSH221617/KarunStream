# **Product Requirement Document (PRD)**

## **Project: KarunStream — LAN Chat & High-Speed File Sharing**

## **1\. Overview**

### **1.1 Summary**

**KarunStream** is an internet-independent, cross-platform local area network (LAN) application designed to facilitate real-time chat and high-speed file transfers. The system consists of two core components: a lightweight, robust **containerized Python-based LAN Server/Daemon (Docker)** and an intuitive, cross-platform **Flutter-based GUI Client** that runs seamlessly on Mobile (iOS, Android), Desktop (Windows, macOS, Linux), and Web browsers.  
┌──────────────────────────────────────────────────────────┐  
│                      Local Wi-Fi / LAN                   │  
│                                                          │  
│   ┌───────────────┐     UDP / mDNS Discovery    ┌───────────────┐  
│   │ Flutter Client│ \<─────────────────────────\> │ Docker Server │  
│   │ (KarunStream) │      WebSocket (Chat)       │   (Python)    │  
│   └───────┬───────┘ \<─────────────────────────\> └───────┬───────┘  
│           │                                             │  
│           │            Direct TCP Socket / HTTP         │  
│           └─────────────────────────────────────────────┘  
└──────────────────────────────────────────────────────────┘

### **1.2 Problem Statement**

Existing file and text-sharing services suffer from severe platform fragmentation, privacy vulnerabilities, or structural limitations:

* **Platform Lock-in:** Proprietary systems like AirDrop or Quick Share do not work natively across mixed environments (e.g., transferring from an iPhone to a Windows PC, or an Android phone to a Mac).  
* **Internet Dependency:** Web-based tools (WeTransfer, Slack, email) require routing traffic through external cloud servers, consuming cellular data, introducing latency, and risking data privacy breach exposure.  
* **Discovery Friction:** Setting up manual IP addresses, shared network folders (Samba), or FTP links is overly technical and complex for non-technical users.

### **1.3 Goal**

The business and technical goal of KarunStream is to deliver an **offline-first, zero-configuration local workspace utility**. It must auto-discover peers instantly on any LAN, utilize the maximum available physical network bandwidth for transfers, protect privacy by keeping data strictly inside the local subnet, and offer a unified UX across all operating systems.

## **2\. Scope & Out of Scope**

### **2.1 In Scope**

1. **Zero-Conf Peer Discovery:** Automatic discovery of local server nodes using Multicast DNS (mDNS) or SSDP without requiring manual IP address entries.  
2. **Cross-Platform Client (Flutter):** Consistent user interface and functional consistency across Windows, macOS, Linux, iOS, and Android.  
3. **Real-Time Local Chat:** Low-latency ![][image1] and room-based text broadcasting mediated by the Python LAN server using WebSockets.  
4. **High-Speed File Transfer:** Support for multi-file transfers, chunked file uploads/downloads with direct SHA-256 integrity verification, and dynamic speed/progress tracking.  
5. **Multi-Interface Support:** Ability to dynamically bind and listen across multiple network adapters (e.g., active Wi-Fi and Ethernet connections).  
6. **Local Encryption:** Encryption of localized payloads (TLS over local sockets) to secure file streams in shared public networks (e.g., coffee shops, co-working offices).  
7. **Dockerized Server Deployment:** Containerization of the Python backend for simplified developer setup, unified runtime environments, and seamless headless hosting.

### **2.2 Out of Scope**

1. **WAN/Internet Routing:** No STUN/TURN/ICE server integrations or relay proxies over the public internet. Communication must fail safely if the device is disconnected from the local network.  
2. **Persistent Remote Accounts:** No OAuth, external database identity management, or cloud sign-ups. User profiles exist strictly in memory or local configuration files (nickname \+ auto-generated UUID).  
3. **Real-Time Audio/Video Calling:** Live streaming, VoIP, or screen sharing capabilities are deferred to future versions.  
4. **Permanent Server Database Backups:** The Python server acts as an ephemeral coordinator; message history and transfer logs are stored strictly on the local client filesystems.

## **3\. User Personas & Use Cases**

### **3.1 User Personas**

#### **Persona A: Alex, the Cross-Platform Creator**

* **Role:** Freelance Graphic Designer.  
* **Devices:** Windows Desktop workstation, macOS laptop, and an Android Phone.  
* **Pain Point:** Constantly needs to transfer heavy raw images and raw video sequences between different operating systems. Uploading to Google Drive takes hours on asymmetric residential internet, and USB flash drives are physically tedious.

#### **Persona B: Sarah, the Field Research Coordinator**

* **Role:** Project Manager for outdoor event production.  
* **Devices:** iPad and a Windows laptop.  
* **Pain Point:** Operates in remote venues or convention halls with poor or non-existent cellular reception. Needs to quickly update run-of-show spreadsheets and send instant updates to her onsite team using a local router.

### **3.2 Use Cases**

#### **UC-1: Peer Auto-Discovery**

* **UC-ID:** UC-1  
* **Title:** Automatic Discovery of LAN Server Node  
* **Description:** The user launches the Flutter Client application, which automatically finds and establishes a handshake with the running Python Server daemon (running in Docker or bare metal) without user intervention.  
* **Pre-conditions:** The Python Server is running in a Docker container (or bare-metal) on at least one machine connected to the same subnet as the Flutter client.  
* **Post-conditions:** Client displays an "Online" status badge and a list of active network participants.  
* **Main Flow:**  
  1. User opens the KarunStream Flutter client.  
  2. Client starts a background mDNS / UDP broadcast listener looking for service type \_karunstream.\_tcp.  
  3. The Python server container, which is advertising its presence (relying on host networking), detects the query or receives the broadcast directly.  
  4. Python server returns its local host IP address and port configuration.  
  5. Flutter client initiates a WebSocket connection to the server, registering its local user profile (Nickname, Avatar index, and dynamic UUID).  
* **Alternate / Error Flows:**  
  * *A1: Multiple Server Instances Found:* Client displays a quick-selection modal showing available local rooms/servers, prompting the user to select which server node to join.  
  * *A2: No Server Discovered:* Client transitions to "Offline Mode," displays a fallback troubleshooting guide, and presents a manual IP address entry field or a QR code scan option.

#### **UC-2: Real-time LAN Chatting**

* **UC-ID:** UC-2  
* **Title:** Peer-to-Peer Subnet Messaging  
* **Description:** Two or more users connected to the same LAN server exchange text notifications, code snippets, or quick links.  
* **Pre-conditions:** Discovery is complete (UC-1), and the client is registered on the active server instance.  
* **Post-conditions:** Messages are rendered in chronological order with sender metadata and a local timestamp.  
* **Main Flow:**  
  1. User selects either the global "Lobby" channel or a specific online peer in the Flutter UI.  
  2. User inputs a text message and clicks "Send."  
  3. Flutter client serializes the payload to JSON and dispatches it over the active WebSocket interface.  
  4. Python server parses the destination parameter, appends server-side receipt timestamps, and relays the message payload to the recipient client(s) over active socket connections.  
  5. Recipient client plays an unobtrusive audio alert and displays the incoming text message in real time.  
* **Alternate / Error Flows:**  
  * *A1: Connection Interrupted:* If WebSocket connection state transitions to closed, the unsent message is greyed out, marked with a "Delivery Failed" indicator, and cached locally for a manual retry attempt.

#### **UC-3: High-Speed File Transfer**

* **UC-ID:** UC-3  
* **Title:** High-Bandwidth Direct File Upload and Download  
* **Description:** A user selects a multi-gigabyte folder or file and transfers it directly to another user on the LAN.  
* **Pre-conditions:** Active WebSocket communication is established. Destination disk space is sufficient to accommodate incoming payload.  
* **Post-conditions:** The file is completely transferred and written to the recipient's target download directory; hash signatures match perfectly.  
* **Main Flow:**  
  1. Sender drags and drops a file into the Flutter Client interface designated for a specific recipient.  
  2. Flutter client issues a FILE\_OFFER JSON schema over WebSockets containing metadata (Filename, Extension, Size, Hash checksum).  
  3. Recipient receives a prompt in the UI to "Accept" or "Decline" the file.  
  4. Upon acceptance, the recipient client opens a designated local TCP listener port (or requests a stream from the server).  
  5. Sender transfers binary chunks directly utilizing a TCP stream (or uploads to Python server's temporary memory buffer acting as a fast relay).  
  6. Both sender and recipient UI render progress bars updated via real-time stream chunk calculations (Current speed in ![][image2], Percentage completed, ETA).  
  7. Once transmission ends, the recipient verifies the calculated SHA-256 hash. If matching, the file status transitions to "Completed" and is written to disk.  
* **Alternate / Error Flows:**  
  * *A1: Low Disk Space:* Recipient's local file utility warns of insufficient space, blocking acceptance of the file pre-transmission.  
  * *A2: Middle-of-stream Drop:* Network drops during transfer. The receiving client retains already-downloaded chunks, allowing the transfer to auto-resume once connection re-establishes (byte-offset resume support).

## **4\. Functional Requirements**

### **4.1 Discovery and Core Network Bindings**

* **FR-1 (mDNS Broadcast):** The Python server must advertise its host IP and active HTTP/WebSocket port using zero-configuration mDNS protocol under the \_karunstream.\_tcp identifier.  
* **FR-2 (Multi-IP Bind):** The Python server must bind to 0.0.0.0 (all interfaces) to support concurrent Wi-Fi, Ethernet, and localhost Loopback connections.  
* **FR-3 (Heartbeat Keepalive):** The client must send a small heartbeat ping to the server every ![][image3] to maintain active socket paths and immediately identify drops.

### **4.2 Chat Services**

* **FR-4 (Message Schema):** All local text packets must adhere to a standardized JSON schema containing unique message IDs, sender IDs, content, type (text, system, link), and timestamps.  
* **FR-5 (History Management):** The Flutter client must cache chat messages in a transient, volatile local memory stream or secure SQLite container.

### **4.3 File Distribution Subsystem**

* **FR-6 (System File Picker Integration):** The Flutter app must open native native-system file selection interfaces (macOS Finder, Windows Explorer, Android Document Provider, iOS Files).  
* **FR-7 (Chunked Memory Handling):** File transfers must execute in configurable binary chunks (e.g., ![][image4] or ![][image5] packets) to prevent heap overflow issues on memory-constrained mobile devices.  
* **FR-8 (System Directory Save):** Incoming files on mobile devices (Android/iOS) must be saved into a dedicated user-accessible "Downloads" or "KarunStream" application folder. On desktops, they should default to the native Downloads folder.

### **4.4 User Settings & Profile**

* **FR-9 (Profile Configuration):** Users must be able to change their local nickname and select a custom profile avatar/color theme within the UI.  
* **FR-10 (Notification Toggle):** The client must support switching system-level desktop/mobile audio/visual alerts on or off for incoming transfers and chat messages.

## **5\. Non-Functional Requirements**

### **5.1 Performance**

* **Throughput Maximize:** Direct file transfers must saturate at least ![][image6] of the available network interface card (NIC) bandwidth (e.g., up to ![][image7] on a ![][image8] wired LAN, or up to ![][image9] on ![][image10] standard Wi-Fi).  
* **Low RAM footprint:** The Python server daemon must run with fewer than ![][image11] of RAM at idle inside its Docker container. The Flutter desktop client must run with fewer than ![][image12] of RAM.  
* **Discovery Latency:** Discovered server instances must render in the UI within less than ![][image13] of the client application launching.

### **5.2 Security**

* **Local TLS Encryption:** High-speed socket servers and HTTP endpoints should run over local HTTPS/WSS utilizing self-signed SSL/TLS certificates generated dynamically by the Python daemon on startup.  
* **No Cloud Traversal:** Zero packets (metadata, chats, binary chunks) can leave the client's local subnet.  
* **Path Traversal Prevention:** The Python server must strictly sanitize incoming filenames to prevent directory traversal exploits (e.g., stripping ../ relative path operators to prevent unauthorized writing outside target directories).

### **5.3 Reliability & Monitoring**

* **Graceful Degrade:** If the network interface transitions from Wi-Fi to Ethernet, the app must renegotiate state profiles within ![][image14] without crashing the application.  
* **Log Management:** Write logs locally to rolling file configurations (app\_debug.log) constrained to ![][image15] in size with up to ![][image16] rotations to avoid storage bloat on mobile devices.

### **5.4 UX & Accessibility**

* **Adaptive Theme:** Seamless dark and light mode UI options based on system preference settings.  
* **Accessible Typography:** Support dynamic scaling of UI font sizes conforming to operating system accessibility preferences.  
* **Touch Targets:** Tap targets on mobile screens (buttons, active avatar toggles) must exceed ![][image17] in accordance with mobile design guidelines.

## **6\. Integration & API Hints**

The core of the server runs as an asynchronous Python engine (e.g., utilizing FastAPI \+ uvicorn or python standard library asyncio for raw sockets).

### **6.1 Server API Endpoints**

#### **GET /api/v1/system/status**

Returns general network configuration details of the active host.

* **Response:**  
  {  
    "status": "healthy",  
    "server\_id": "8f3b2319-3f09-4ce4-82a9-7eb89781bbca",  
    "version": "1.0.0",  
    "active\_peers": 4  
  }

#### **GET /api/v1/peers**

Fetches a list of currently registered active peers in the session.

* **Response:**  
  {  
    "peers": \[  
      { "peer\_id": "u1", "nickname": "Sarah", "platform": "iOS", "ip": "192.168.1.15" },  
      { "peer\_id": "u2", "nickname": "Alex", "platform": "Windows", "ip": "192.168.1.20" }  
    \]  
  }

#### **POST /api/v1/files/upload**

High-speed HTTP multipart upload endpoint for small/medium files.

* **Header Parameters:**  
  * Content-Type: multipart/form-data  
  * X-Sender-ID: \<uuid\>  
  * X-Recipient-ID: \<uuid\>  
* **Body Content:** Raw binary stream.

#### **WS /ws/orchestrator**

The state connection used to transmit peer signaling, global chat messages, and file invitations.

* **WebSocket Message Examples:**  
  * **Chat Event:**  
    {  
      "event\_type": "CHAT\_MESSAGE",  
      "payload": {  
        "msg\_id": "m109283",  
        "sender\_id": "u1",  
        "receiver\_id": "global",  
        "body": "Hey everyone\! Ready to test this stream?",  
        "timestamp": 1718290312  
      }  
    }

  * **File Transfer Proposal:**  
    {  
      "event\_type": "FILE\_OFFER",  
      "payload": {  
        "transfer\_id": "t9821a",  
        "sender\_id": "u2",  
        "file\_name": "ProjectMasterclass.mp4",  
        "file\_size": 2451092834,  
        "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"  
      }  
    }

### **6.2 Containerization & Deployment Details**

The Python server will provide a Docker image utilizing a multi-stage Dockerfile based on a lightweight Python Alpine or Debian-slim base image to guarantee a minimal resource footprint.

* **Network Run Configuration:** To ensure mDNS (UDP multicast) packets bypass the virtualized container bridge and map directly to the host's actual network, the container should ideally be run with host networking.  
  * **Command example (Linux):** docker run \-d \--network host karunstream-server  
* **Port Mappings (Non-Linux Fallback):** For platforms where host networking is restricted (macOS/Windows under virtualized hypervisors):  
  * **Ports to Expose:** TCP 8080 (HTTP/WebSocket API) and UDP 5353 (mDNS fallback listener).

## **7\. Analytics & Success Metrics**

To honor the absolute privacy-first design constraint of this product, **no metrics or tracking telemetry shall ever be uploaded to remote external servers**. All analytics metrics are stored strictly in local application memory and rendered inside the user's dashboard view.

| Metric | Target Goal | Method of Measurement |
| :---- | :---- | :---- |
| **Transfer Completion Rate** | **![][image18]** | Calculated inside client app as successful versus aborted file transfers. |
| **Discovery Success Rate** | **![][image18]** | Measured as successful socket handshakes after a discovery packet scan. |
| **Average Local Throughput** | **![][image19]** (wired) / ![][image19] (Wi-Fi) | Built-in byte counters dynamically averaging speed rates across files larger than ![][image20]. |
| **Reconnection Latency** | **![][image21]** | Time elapsed for automatic reconnect logic to regain session status after network loss. |

## **8\. Risks & Open Questions**

### **8.1 Critical Risks**

1. **Isolation Protections (mDNS Blocking):** Many enterprise office environments, co-working networks, and public guest routers deliberately enable AP isolation (access point isolation), which blocks peer-to-peer multicast UDP broadcasts and client-to-client IP connections.  
   * *Mitigation:* Create a highly visible "Manual Connection" option in the UI, enabling users to generate and display a scan-friendly local QR code containing their device IP and active port configurations.  
2. **OS Sandboxing & Write Permissions:** Mobile platforms (iOS and Android 11+) restrict local directory scopes, while desktop environments might prompt security warnings if a third-party non-sandboxed program tries to write files into restricted regions.  
   * *Mitigation:* Flutter clients must request storage permissions upfront on launch and default writing directly to sandboxed Application Directories (getExternalStorageDirectory on Android or Document containers on Apple platforms).  
3. **Docker Host-Networking Limitations (macOS & Windows):** On Windows and macOS, Docker Desktop runs containers inside a lightweight Linux Virtual Machine (VM). Running a container with \--network host binds to the *VM's* network stack, meaning standard mDNS/UDP multicast discovery packets won't naturally broadcast onto the user's *physical physical LAN host adapter*.  
   * *Mitigation:*  
     1. Direct users on macOS/Windows Docker to expose explicit port mapping and rely on client manual pairing (IP input or QR codes).  
     2. Recommend running the server via bare-metal Python binaries for non-technical macOS/Windows users, reserving Docker for Linux server setups, headless NAS hosts, or advanced users.

### **8.2 Open Questions**

* *Should we distribute the Docker server image on Docker Hub?* Yes, an automated CI/CD pipeline should build multi-platform (amd64, arm64) images and publish them to Docker Hub. This makes hosting the backend on a home server (such as an Unraid or Synology NAS, or a Raspberry Pi) remarkably simple.  
* *Should we support multi-threaded file downloading?* For Phase 1, single-connection TCP stream transfer is sufficient to simplify memory allocation and minimize potential socket locks. We will review multi-threaded byte ranges for Phase 2 optimization.

## **9\. Acceptance Criteria**

┌───────────────────────────────────────────────────────────────────────────┐  
│                           Acceptance Criteria Matrix                      │  
├───────────────────────┬───────────────────────────────────────────────────┤  
│ Verification Area     │ Success Condition                                 │  
├───────────────────────┼───────────────────────────────────────────────────┤  
│ 1\. Discovery          │ Launch server, open app \-\> Auto-pair inside \< 3s  │  
│ 2\. Data Integrity     │ Transfer 1GB zip \-\> SHA-256 verification matches   │  
│ 3\. Speed Validation   │ Giga LAN transfers files at \> 90MB/sec sustained  │  
│ 4\. Crash Resilience   │ Disconnect cable \-\> Transfer halts gracefully     │  
│                       │ Reconnect cable \-\> Resumes without corruption     │  
└───────────────────────┴───────────────────────────────────────────────────┘

The system is considered feature-ready for QA signing and release production when it meets the following operational scenarios:

### **Scenario 1: Zero-Configuration Setup**

* **Given** a network subnet with a running Python Server host and multiple devices running the Flutter Client (Windows and Android).  
* **When** the user launches the Flutter Client application on both devices.  
* **Then** the client must identify the server, join the default chatroom lobby, and populate the online roster within ![][image22] without prompting the user to type any network address settings.

### **Scenario 2: High-Volume Data Integrity**

* **Given** two peer devices on a standard Wi-Fi network with an established handshake session.  
* **When** a user transfers a ![][image23] archival file (Archive.zip).  
* **Then** the recipient device must display a dynamic progress bar continuously updating average throughput speed, complete the physical download, calculate the SHA-256 hash, and match it with the original hash, writing the file successfully to the client's localized default directory.

### **Scenario 3: Graceful Offline Recovery**

* **Given** a file transfer is actively running between two connected peers.  
* **When** one of the peer devices experiences a sudden, temporary network loss (e.g., Wi-Fi drops out or a network cable is unplugged).  
* **Then** the Flutter client UI must transition smoothly into a "Paused/Waiting" state, retain the partial transfer bytes cache, prevent application lockups or interface crashes, and resume download from the last verified block when connection re-establishes within a ![][image24] window.

## **10\. Monorepo Structure & Build Orchestration**

To simplify development, keep API signatures and WebSocket schemas unified, and streamline the containerization process, **KarunStream** is structured as a single unified monorepo.

### **10.1 Directory Architecture**

The workspace layout is structured as follows:  
karunstream/                    \# Monorepo Root  
├── .github/  
│   └── workflows/  
│       ├── backend-ci.yml      \# Docker builds & Python testing pipelines  
│       └── frontend-ci.yml     \# Flutter multi-platform build pipelines  
├── backend/                    \# Python Server Component  
│   ├── app/  
│   │   ├── \_\_init\_\_.py  
│   │   ├── main.py             \# FastAPI entry point  
│   │   ├── core/  
│   │   │   ├── config.py  
│   │   │   └── security.py     \# Local TLS cert creation  
│   │   ├── services/  
│   │   │   ├── discovery.py    \# mDNS advertising engine  
│   │   │   └── sockets.py      \# WebSocket orchestrator  
│   │   └── api/  
│   │       └── routes.py       \# REST endpoints  
│   ├── Dockerfile  
│   ├── Dockerfile.dev  
│   ├── requirements.txt  
│   └── tests/  
├── frontend/                   \# Flutter Client Component  
│   ├── lib/  
│   │   ├── main.dart  
│   │   ├── models/             \# Client representation of Shared Schemas  
│   │   ├── services/  
│   │   │   ├── discovery\_service.dart  
│   │   │   ├── socket\_service.dart  
│   │   │   └── transfer\_service.dart  
│   │   └── views/  
│   ├── pubspec.yaml  
│   └── test/  
├── shared/                     \# Centralized Contract Definitions  
│   └── schemas/  
│       ├── chat\_message.json   \# JSON schema for WebSocket chats  
│       └── file\_offer.json     \# JSON schema for WebSocket file proposals  
├── docker-compose.yml          \# Orchestrates local testing backend \+ mock dependencies  
├── README.md  
└── .gitignore

### **10.2 Shared Contract Integration**

By placing raw protocol definitions inside shared/schemas/, both the **Python team** (utilizing pydantic generators or JSON validators) and the **Flutter team** (utilizing tools like json\_serializable or matching model contracts) can program against the exact same network schemas.

### **10.3 Development Commands**

* **To spin up the local development Python backend inside Docker:**  
  docker-compose \-f docker-compose.yml up \--build

* **To run the Flutter client (Desktop/Mobile) in development mode:**  
  cd frontend  
  flutter run  


[image1]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADYAAAAZCAYAAAB6v90+AAAAn0lEQVR4Xu3P4QqAMAgE4L3/SxcLhHF4ztmKoPtgP2aes9ZERMR3wPmSLbvdCr+gvJt+DFQyFeV3nvgxbybes6o5d4kMlmHzvFpGNUcXmWGZaB6rRyqZC1vE6uMZ4d14vcbqOJf1d9G3EBuMD2MP3o3Xa6yOc1l/F30LzQYzmMGlkVfLqOboIjNjBvPeTLxnLefscTwrotyuuXhEROS/TpCebJQQ1zEYAAAAAElFTkSuQmCC>

[image2]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADQAAAAZCAYAAAB+Sg0DAAAAyUlEQVR4Xu2QUQoDQQhD9/6XbrEwYNMkOvtRhsUHQsckrva6hmEYCC8oh/JiH+vvdD6+NOVxeachXZ8lL6sGzkEJp2U6nhZ5EBta6YFb2mmZjqdFtXClB2tpVh2UD/v4pqAJ3xmlueVVP6M8qm/BEL4zSqsOUtpC6Z3sDxjIQ5jGcB9emtMdOV95P6DptIOCasYXzKTCrBcof7C1DHAnQ0NqAdYLlD9wWsV2Lv97OYy/WVU6+hgdHetojl9wh0cdE8xBJ/OoY4YOb3MhpFzWXtyYAAAAAElFTkSuQmCC>

[image3]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAF4AAAAZCAYAAAC4j5m6AAABGklEQVR4Xu2Qy2oDQQwE/f8/7aCDQDTVkrMPhywqmIOqe+Txvl7LsizLsix/yLucy6hLu8WU6/xk6P9fwrSYMnJPZfo+h+kWu4zcU3Hf4DTdYpeReyruG5ymW+wy5yua3z0H6vKd1etcIU99mtWNdJdc5nyly+l+nY/kgbrsOT+5gLzOAbkWWpy4zPlK13FZOpcnLlevc0KeXEA+nfpf0S1wmfNKfWDtq9eO9hWXq9c5IU8umLzLR7qLLiPnoMfprBzN1euckCcXOJ9k3nWQ6RJl5JSu434z3dm8zuoC8uQC8joH5FpocYVynYmpc0eujt4edF6hrnMfkZf1EOmnXkX30p1v53oI7VBfvdt1CbcuX5ZlWZZlWf4DPzGYCQaWxriAAAAAAElFTkSuQmCC>

[image4]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADkAAAAZCAYAAACLtIazAAAA4ElEQVR4Xu2PSw5DMQgDc/9Lt8pT84Rc24DaTVVGYgEe8llrGIbhR3nggLAdrAhmMcc5VhlcwJ7RvajjMtRu+VyUKovf/KSaR5zjshuUsEdO7h6OKJfNGM5z2YW6vEJnl7nYO5zrsovu5TFjuwp0sc84PqsUJrLZBmfKY0S3/cilvdIZTGKzDc6Ux2Cfwt7hPJddMIFdjv2GeQrmso8rnJOewUK2FB/EKkN5ao44p3QGCqWlVfc2znXZweWV/TcBe0Xp8BeZW8kZ2d7NEWM50P3UxyzmOGfVor0wDMMw/CNPSiTAQDLWCdsAAAAASUVORK5CYII=>

[image5]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADIAAAAZCAYAAABzVH1EAAAAq0lEQVR4Xu2PUQqAMAxDd/9LK4EKsyTZqj8ifVAcaV/dxmiaptnkSOVQsznPVeKVPPY9N+dy51HKQrD7MzejcuA8SlkIfvWQ68v8VR+oHDiPUhaC1UVXfXD1WJV5Ks5O3pHPar/LVU/ySBr+svms9qscOI9SFgJ12bzL7Vc5cB6lLATZ+c1DgMpYDlQOnEcpCwFzVMZy4HLn3ZiHK+LufJ6bZ3POqmmapvkeJ2Wcn2Fb71MUAAAAAElFTkSuQmCC>

[image6]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACYAAAAZCAYAAABdEVzWAAAAvUlEQVR4Xu2QWwrEMAwDe/9L72JogplKTgL92AUPBCpZftDrapr/5nO/ilX9dfJCd6DyHjBEHagF1MFJrsQNUh5xOeVVWqJCO8MDl1Oe+i5RwdXwgcoF1SHUFhVUC6mDkatqWR/DJg4dHqkOI8xs9TGgmqiDk8MyuafszQvcMurAZQnrK21Ry6gDlVMws9ITFqgD5yl/4Gr0qScsUAfqCGri6vSpJ2OpWp7J9Z2sg3NKloHESdax8yOapvkJvgf4gX8BZflzAAAAAElFTkSuQmCC>

[image7]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAG8AAAAZCAYAAAA/vnC8AAABVUlEQVR4Xu3TgWrDQAwD0Pz/T29ocGCMZOvSjCTFDwKtLZtcjx7HGGOMMca43U96Oiyfa/n5Ss4hnYyyk3f2d+9R1au5yMk8yhUHYz13L6xcle8uQdWhmouczKNccTC2g9WUJ1xe138k52BQZdgOVlPi5bGZrg+qDtXc0vUfyTkYOJnI3Qvd5XR9WD32dJzMspP9s/MyXT9zdoKTiXbyMZvfJ39We6u66i1dP9rJUtWCqsc4hwMns+xkobqg/FntVnWo5qDrVf0SG1QLWa2jdmVOBtx9UcyvebaH1RZVh7NzUL1PqxqIC08tP/w5N+PksjyjfixWW1Qdzs5F6p1u5b5Ql2F9VmNYTtVYHVQd1Byrdc7M/Bt1sKzLrD35cbCcqrE6VHU1x2pZzuTvt8g/Mjtg7n2ay6ps/J5zMZ9r7PnElbvGGPMverG5vBeby3upubgxvtIvOUgNAjlOjGwAAAAASUVORK5CYII=>

[image8]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAD4AAAAZCAYAAABpaJ3KAAAA3ElEQVR4Xu3SywrDMAxE0fz/T7dokeKoV09wIEQHushY4yqlxzHGGCPlAx8Snd8ms6wn6tFZ1LlVd5lup9PborNMpyO6vS06y3Q6otvborrMOV/pnKwuZYJyK9PPOvuTGlpYy2dYPS/XaFY/C8ou6CLPjhcXlFMm9D2tncqFw+6sC9Ay+nlFOWWC7rG+05QeXGQ6dO71KKdMRPd45z+pIRD16MzqeLlGs/pZUHZBF2VZ3SjXZ5QJyisZWpewForobnTPmlfmo1l9TjOP8vgX6Hrdi+u/7et+gDFGzRfiL7NNwXD8MgAAAABJRU5ErkJggg==>

[image9]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIMAAAAZCAYAAAASYJ1DAAABq0lEQVR4Xu3SiWoCQAwEUP//p1sipITpzCTrUbXkgeBODnfBy2WttdZaa631VF/w6bB+zPDzL00eyWp4PsFmWRZUPsHujSZvZ7q5atLzFiaPYrVuxmFzJ/tO+1x/936VBzdXTXo+gnqwyifUHOZ4TipH2ef68x2qR+XBzaWu/lHUg1U+wWZVxqgcZR/bHbp6UHlwc6mrvxV8EF4e60nlUznv9rhc1arsUf1dPeA9uztXk5500nt1cpmuruBuPCeVn+jew7Kg+pF7B35X+1yuaqmrVye9lFvgag4+Es8J8zy7T6pn1ZM1hvUy6jfzXL+rfSoPbi50NVe32KBayLIp3InnpPIOm8uM5QzrZdg72CzLksrDrXPB3aflBurCk+WsD+fxnFTecXOY4zmpHGFf/rbKGZWHW+cqdac/xy7ALobnwPom3JzK0T19KmN5UHlQcyzr3DLzdOxS7NF4PsFm2W8Elk2xWZWxPLhczbEMYQ+eX6I+yl0I+1zvBO5S+2rN9VVubz1jH/st97nHI3c93NtdCLz7/db6Zf+068f+GdaP/TOsq/0jrLVe4BsipE+/7m2aSAAAAABJRU5ErkJggg==>

[image10]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAE4AAAAZCAYAAACfIRhSAAABDUlEQVR4Xu3PQYoEMQxD0b7/pWcwTMB8JEfFUL3yg15EllPpz2ettdZa7/th8KdyznguzHienG+ob3Vp76vcY5Lsye7E3UNp72v4GPdAZmnvxt1Dae8V/LB6jMoKs7R34+6htPeK8/HpEW7m8i7pULrjeur/8Nwx59nqH1JLT/PuNleSe8vU44znQ+U8S+pyLqqsuPy4zZ10L+0V13X5SC2oi1RWXF6m2U26e+udef+Ry0dugZfxfKisuH4q3Z96nPF8uHzkFlSeZgp7t8fe5ofrqbxnfaa6RWWj6SLmPJfT469z+THNOtdTec/U7DFeOF3CHrs9569TWeHOf3pqxnOn+pG0nPbWWmuttQa/lMvmGv3CalcAAAAASUVORK5CYII=>

[image11]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADwAAAAZCAYAAABtnU33AAAA60lEQVR4Xu3P0Q7CMAxDUf7/p0FBKirWdePuOUeaWOMko6/XGGMM9JbnxPVqXZ8r6TDlenbS/fsvcVmy/ydtppxq5OYySQ9J7hBzy6hGbi6T9BD3Hx9xy6hG9j6a6fKly075jzbSkPYsrq6S/fSu1vfoeYwWUK24utIL6Xmn553LdOcVGqZacXWlF9TzTs+7LjvlFg1Srbi60gue5ly9dNkp/6IGGqRaoRrRPrevuHrpslP+RQ1uMK0R6rv5ztJlp9xyQ7RQzw710b5CtcVla5fL/+zN3cDK0/7i9us7PV1OvbF0KO0bY4wxQh/nW75C2gq1XQAAAABJRU5ErkJggg==>

[image12]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEYAAAAZCAYAAACM9limAAAA+ElEQVR4Xu3Q0UoFQQyD4X3/l1Z7UVhj/nTmgHf9YMFJm4o+z1prrfXjS76EdjXX78ppWfdol/JT6fZb2kt56llT4fSom7uM3Pwe2qG8pJ41FdKs0Q2Xkf3HgN6dbtG8UF5Sz5oKOtc3ZYVyZ/rDp3npmfuuTUU3046+G+VOuqc/082U0wx9UtKOvhvlTrqnP9NNykvqWdeF529H341yh+5pP92kvKSelQo001zfzWVEd/vtcs0a5SX1rFSgmcv1XVxG3C5lLi+Ul9SzpoLOaN9lN1yfMpeXlKfeL+/lqXiyU3o27b3d3NYvzfT7N6fHT/fWWmutZX0DCwDnGaosVN0AAAAASUVORK5CYII=>

[image13]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGQAAAAZCAYAAADHXotLAAABOklEQVR4Xu3U0arjQAwD0Pz/T7f4weAKyeOhSQqpDgTWssfp5MIeh5mZmZkdr/KcDpfuvKj+sJ1zT3HJfdnS6cf91z9EuuTe7IOyjJnMPNkl92cfn2XMZObJbrn/zn9DODc5E3CO7VF112O1ygLLsQ5qDjNmMtOaviiwOZYhNpMZe3/Nul7WCGcSyzHDulJ5NZlpfbtgcj4vyWZXOetVqs/OYh1wDuuK5d38tjMWTXfUD8w+QPd0VJ+dxTrgHNYVy3d+a2t3gZpnWQd/vNqbul5QfbYX64BzWFcqD3ivLewQZrgc68QyxGYy6/aqXqjnkTqnsppjXam8msx8qBfFp1JZVyurXV2/6+W/WR+zoDLMp1nADOulXMyeimWhO6PgGXau63e9sOoHNsOyxHrTudv97MVmZmZmZtobgi8GCXr1KAoAAAAASUVORK5CYII=>

[image14]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFQAAAAZCAYAAACvrQlzAAAA9ElEQVR4Xu2Qyw6DQAwD+f+fbpVDpGjkQICt+vJIHHbsZIFtM8YYY8xH8SjPMurS5cu/gOXf/M8/M1j+3UuXfSH+oYt5yQ+tS6cXsMO51ed0hD2eK8qzzw7zQ1R5skTl6dR8dVfyoHP0UxfQd51b8BLFXqfL0nV5spfT8xyoeeUC+jyr7mWmC+vl3UvxqXnHXk7Pc6DmlQuUV+88Rg2cWaQuP5q/k9PzHKh55YLOB5l1uUSVJ0tUnq6bP8qTLj/j6JUL6LvOGJZ5QYfq8cVemSed6zxhl+d0p8glalkHZ9TcO3LlKszZpVM7xtwaNsYYY4z5PZ6dkO8R1wpw+wAAAABJRU5ErkJggg==>

[image15]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADwAAAAZCAYAAABtnU33AAAA50lEQVR4Xu2Pyw7CMAwE+/8/DcohklnvI5HghEeqIDtet3meYRiGgfKCx6FmMcfnitMy83hWnO6vvwzlTvY3UoE5ljFuLnMyw0jf33AF5VjGuLnMyQxDfaPEFZRjGaPOsU7ym+Scb7iCcipH0oWS3+z3secaV1RO5QheCM8VPFeUw51HuJJyKkfwgniu4LmSnPMNV1BO5Qhe0PVUvkjO+YYrKMcyBs6pfQuVL5JzvpEKzLGMwebU+1i2Sc75Riowj2cFm2P7FizbKLd3Kf9BHU7Fnae5itqL/9mTPJv9Oj9dPgzDMPwjb+rhwEDUkEWaAAAAAElFTkSuQmCC>

[image16]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAoAAAAbCAYAAABFuB6DAAAARElEQVR4Xu2P0QoAIAgD9/8/XRQJMpcYvXogyHYIAg0waCRcXGUO/0UmFUvPeMri4lkuEa6G4BAyJaps4wvbpWikZSOZ/x4m2tumHsIAAAAASUVORK5CYII=>

[image17]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAHsAAAAZCAYAAAAR+1EuAAABjklEQVR4Xu2U22oEMQxD+/8/3ZIHgxGSL/F2y059YB5GOYqTWdivr2VZlmVZluVj+MYgoON6Ts+eT6B6zqqH/Mn3qA58xeGm/XfQuWfVU0z7baoDOx9BMe2/g849q55i2m9hg7KB3svciGn/t+nc05zMi5j2y/gh1YHTw037imzPbB3JzmlrmZcx7ZfAAfju8Wudw6FnXcwPLGdZBvr4HlG9Z9VDmKf6luMavl+hNsGcHYChHNVXGcsjfKfTRVfNxkx5iPJu8jFqE8zVIRDlqD7LDsqPuO3gO2YHzJSHKK+bH1ROYXInYzmiHNVn2UH5GZ0Oc6tzp143P6icYhupp+sx1Lrqsuyg/Ajzqz28Fz4eXMNHoda7+UHlZaobRIfwKEf1VcZyhXJVHlGdPfVu8jHVTdQhGOhZF/MDy1l2S3ef6uyqd2Ce6qtvhe9l/IZqcwMd5XmYj+8GW0cnInOzdQPnqx46ketBX3V9FnkfySMu8UIe88MyHnuxSx75Y+Nf1OMueMF+j2VZlmX5R/wAyVtFyQjvCUoAAAAASUVORK5CYII=>

[image18]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEQAAAAWCAYAAAB5VTpOAAAAP0lEQVR4Xu3SOQoAIBAEwf3/pxXBA2XNxKgqnLCZCAD4oZwDiziJFkWYhDAXoiTGW8QJESaP6IQIETZCAPBWBeDREe9Ti7emAAAAAElFTkSuQmCC>

[image19]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGIAAAAWCAYAAAA7FknZAAAARElEQVR4Xu3TIQ4AIBADQf7/aQgCQ4JAtWJGnrxNxwAA4M+8D+SJUmTHEKSIIGXEKHLWIUqQ54dZQJgAQZ5fQAAAgJcFhYYR7/lMsxYAAAAASUVORK5CYII=>

[image20]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAD8AAAAWCAYAAAB3/EQhAAABAklEQVR4Xu2PQY4CMQwE8/9Pg4ywhIouZzgAl5QULe5qZ7JrHQ6Hw+Fv3HAmrMucR9kW1vXLrvbI1Z2pY87yB6Nc2aUdzkXKEt2b+rtOelOjTsVyx5xzk7LE7h8rdh17Q6FOxXLHnHOTsgTvIjtf2BsKdSqWO+acm5QleBfZ+cLeUFi+XUqOOefGcjLdxX3ODfdesXy7lBxzzo3lZLqL+5wb7r2iTsVyx5xzYzlJd9nelH/sVCx3zDk3KUuwZ/cVU/6xU/EkubTDuUhZIvXSN4qUFdYv1Kl4kjznImVXSbvpu0XKCusXb64DngQ7U6//WofYvfydzs6z93V++rHD4TByB3rR6xX5eWjZAAAAAElFTkSuQmCC>

[image21]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAF8AAAAWCAYAAACmG0BRAAAAQUlEQVR4Xu3SMQ4AIAwDMf7/aRArzLRBsseOuY4BAMBtngfeMniDPbrhixm9idGL+fQAIgQQIYAIIYQIIAAA8IcF4YYR7095ko0AAAAASUVORK5CYII=>

[image22]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFQAAAAZCAYAAACvrQlzAAAA9UlEQVR4Xu2R0QqEMAwE/f+fviMPgTJstNXIlWMHfMhsklY9DmOMMcZsxWd42uCy9gM2p/19ufCVv7Yx7e/Khf6gzfiDNrH6IdnH2e46HWEf6xHl2c8e5svMDqu+dOoSo7uTB5Wjn3UBfdVzmzzgaslZT5Wlq/LkLKdnHah55QL6rFXvbWYXjodXl+Iz5hVnOT3rQM0rFyiv7vyIlWXq8KvZJzk960DNKxdUPsisyiVqQDmi8nTV/FWeVPmKo1cuoK96pmFzHkBPVA8v9maeVK7yhL2s002TC3JILVSMc9XML3LlRpizl07tmObRsDHGGGPM//EF66b0DJvuwrUAAAAASUVORK5CYII=>

[image23]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAHIAAAAZCAYAAADt7nrkAAABkUlEQVR4Xu2S4YoEMQiD9/1f+o7+ECSTWOuNhWP9YGCMMXan+/kMwzAMwzAM1/ghj+/dhJ3hX6A+YAacrc4rVJ9pb6L2/pWOzAeVw1cv0MjM7vodZM5VoSPzQeXwp35P9k+w63eQOVeFjswHlcOf+j3ZfRnP22TPdkJHJqWyCGey8zaX9SM4h1nRO5tF1PmYtshoatbAHtZpdosYzM80RH2oLDjHatQM1LFeqPkTndWoGUxnWopo0QmZDNuV8TJwjtWoKZgvmmd65DciD9Mjf0h5EMhmRPus5x9PpkbNE2UvlL5geuQ3Ig+eJzrbltNB5WcaQ817lAc19GHfgz2sF5jniXTrMU8ls0S0aIF9rA2mKVSGofqoYa1geVZnfxvTDeszD+rq3UB/mt0g6+/qDCx3YbrqYY0Pg/Ws9rrKYZon6ke9Bfaw3uIPrX7AYqerfgbM8FmYqTzqQVgfvfiOfsXOE+Wc7GnjzcWVLDVz+6Pc3PVVdF+kz+/c8zWwC2NaB3ORDdjl3f6ot/cNwzAMffwCjC880o7i0S0AAAAASUVORK5CYII=>

[image24]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFgAAAAZCAYAAAC1ken9AAABF0lEQVR4Xu2RQWoEMQwE9/+f3o0OAlF0G9uT09AFC1G1JI+dzyeEEEII4Y/v+B3DIbdIedZv5+q+fDj332JdKPdmru7Lx1QPzLpR7s38y33zwJ5H91UP25x6wp45xx1Pa+cK5VkXro/uCrXELXeeqJ52zLjzNC/Y0yhPx3ri/BF9wM6hzhO1s3GuvconLlfnsS7Yx3ri/DE8hHXDh+Bv4jJ69nAPcTnPaUfYx3ri/DHqkmq5+jDOEuaur7nN1TewLtjHeuL8ErXQOaKcQvW1c9kqL1a5+v7CuelZT5xfwqE+wHm6HVazq6z/vsnpCufod90WPdjDq0XscX1k9qu5VVY8zQvVo1yjMtV3xM7wTk8IIYQQQrjiB7NEAA9ZF8ybAAAAAElFTkSuQmCC>