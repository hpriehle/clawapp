FROM node:20-slim

WORKDIR /app

# isolated-vm requires build tools for native compilation
RUN apt-get update && apt-get install -y python3 make g++ && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json* ./
RUN npm install --production

COPY src/ ./src/

# Socket path — shared volume with Vapor container
ENV SANDBOX_SOCKET=/sandbox/talkclaw-sandbox.sock

CMD ["node", "src/index.js"]
