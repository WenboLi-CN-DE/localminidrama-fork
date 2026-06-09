FROM node:22-bookworm-slim AS frontweb-build
WORKDIR /app/frontweb
COPY frontweb/package*.json ./
RUN npm ci
COPY frontweb/ ./
RUN npm run build

FROM node:22-bookworm-slim AS backend-deps
WORKDIR /app/backend-node
COPY backend-node/package*.json ./
RUN npm ci --omit=dev

FROM node:22-bookworm-slim
ENV NODE_ENV=production
WORKDIR /app

COPY backend-node ./backend-node
COPY --from=backend-deps /app/backend-node/node_modules ./backend-node/node_modules
COPY --from=frontweb-build /app/frontweb/dist ./frontweb/dist

WORKDIR /app/backend-node
EXPOSE 5679
CMD ["npm", "start"]
