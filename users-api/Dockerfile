FROM node:24.14.0-slim

WORKDIR /app

COPY package.json .

RUN npm install

COPY . .

EXPOSE 3000

CMD [ "node", "users-app.js" ]