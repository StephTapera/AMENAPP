FROM node:18-slim

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy index.js explicitly
COPY index.js ./

# Copy everything else
COPY . .

# Debug: List files to see what was copied
RUN ls -la /app

EXPOSE 8080
ENV PORT=8080

CMD ["node", "index.js"]
