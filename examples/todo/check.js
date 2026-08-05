"use strict";

const fs = require("node:fs");
const path = require("node:path");

const failures = [];
const requiredFiles = ["index.html", "styles.css", "app.js", "todo.js", "todo.test.js"];

function addFailure(message) {
  failures.push(message);
}

function readFile(fileName) {
  try {
    return fs.readFileSync(path.join(__dirname, fileName), "utf8");
  } catch (error) {
    addFailure("unable to read " + fileName);
    return "";
  }
}

requiredFiles.forEach(function (fileName) {
  if (!fs.existsSync(path.join(__dirname, fileName))) {
    addFailure("missing file: " + fileName);
  }
});

const html = readFile("index.html");
const css = readFile("styles.css");
const app = readFile("app.js");

[
  "id=\"new-todo-form\"",
  "id=\"new-todo-input\"",
  "id=\"todo-list\"",
  "id=\"filters\"",
  "id=\"items-left\"",
  "id=\"clear-completed\"",
  "id=\"empty-state\"",
  "data-filter=\"all\"",
  "data-filter=\"active\"",
  "data-filter=\"completed\"",
  "src=\"todo.js\"",
  "src=\"app.js\"",
  "styles.css"
].forEach(function (requiredText) {
  if (html.indexOf(requiredText) < 0) {
    addFailure("index.html missing: " + requiredText);
  }
});

[
  "--bg",
  "--surface",
  "--text",
  "--accent",
  "--danger",
  "--border",
  "--shadow",
  "prefers-color-scheme",
  ":focus-visible"
].forEach(function (requiredText) {
  if (css.indexOf(requiredText) < 0) {
    addFailure("styles.css missing: " + requiredText);
  }
});

let TodoLogic;
try {
  TodoLogic = require("./todo.js");
} catch (error) {
  addFailure("unable to require ./todo.js");
  TodoLogic = {};
}

[
  "addTodo",
  "toggleTodo",
  "removeTodo",
  "clearCompleted",
  "filterTodos",
  "activeCount"
].forEach(function (functionName) {
  if (typeof TodoLogic[functionName] !== "function") {
    addFailure("todo.js missing function: " + functionName);
  }
});

["todo-app.v1", "TodoLogic"].forEach(function (requiredText) {
  if (app.indexOf(requiredText) < 0) {
    addFailure("app.js missing: " + requiredText);
  }
});

if (failures.length > 0) {
  failures.forEach(function (failure) {
    process.stderr.write(failure + "\n");
  });
  process.exit(1);
}

process.stdout.write("OK\n");
