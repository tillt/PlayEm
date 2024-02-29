"use strict";

const fs = require("fs");
const jwt = require("jsonwebtoken");

const privateKey = fs.readFileSync("AuthKey.p8").toString();
const teamId = "";
const keyId = "";

const jwtToken = jwt.sign({}, privateKey, {
  algorithm: "ES256",
  expiresIn: "100d",
  issuer: teamId,
  header: {
    alg: "ES256",
    kid: keyId
  }
});

console.log(jwtToken);
