# Use Debian Stable (slim variant for smaller image size)
FROM debian:stable-slim

LABEL org.opencontainers.image.description="A minimal CLI example using Ink and React for building interactive terminal UIs"

# Copy the setup script and run it to prepare the environment
COPY setup.sh /tmp/setup.sh
RUN chmod +x /tmp/setup.sh && /tmp/setup.sh

# Set the working directory to the path created in the setup script
WORKDIR /app

# Copy the demo file into the source directory
COPY app.tsx ./src/app.tsx

# Execute the build step to compile TypeScript/JSX into JavaScript
RUN npx tsc

# Set the default command to run the compiled CLI tool
CMD ["node", "dist/app.js"]
