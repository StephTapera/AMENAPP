FROM node:18-slim

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application files
COPY index.js ./

# Set environment
EXPOSE 8080
ENV PORT=8080

# Start the server
CMD ["node", "index.js"]
