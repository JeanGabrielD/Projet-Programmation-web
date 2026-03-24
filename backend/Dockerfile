FROM node:20-alpine
WORKDIR /app
LABEL build="20260324031057"
COPY package*.json ./
RUN npm install --omit=dev
COPY dist ./dist
EXPOSE 3001
CMD ["node", "dist/index.js"]
