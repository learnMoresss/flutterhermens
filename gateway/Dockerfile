FROM node:20-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
COPY skills ./skills
COPY public ./public
RUN npm run build

FROM node:20-bookworm-slim AS production
WORKDIR /app
ENV NODE_ENV=production
ARG GATEWAY_VERSION=0.1.0
ENV GATEWAY_VERSION=$GATEWAY_VERSION

COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

COPY --from=build /app/dist ./dist
COPY --from=build /app/skills ./skills
COPY --from=build /app/public ./public

EXPOSE 3000
CMD ["node", "dist/index.js"]
