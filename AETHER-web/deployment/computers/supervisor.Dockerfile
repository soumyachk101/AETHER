# Source comes from the exact AETHER bot revision in compose.computers.yml.
FROM oven/bun:1.3.14-alpine
WORKDIR /app
COPY --from=aether-bot supervisor/package.json supervisor/bun.lock ./
RUN bun install --frozen-lockfile
COPY --from=aether-bot supervisor/src ./src
COPY deployment/computers/harden-supervisor.mjs /tmp/harden-supervisor.mjs
RUN bun /tmp/harden-supervisor.mjs /app/src/environment.ts && rm /tmp/harden-supervisor.mjs
EXPOSE 4300
CMD ["bun", "src/index.ts"]
