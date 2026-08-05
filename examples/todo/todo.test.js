const { test } = require("node:test");
const assert = require("node:assert/strict");
const TodoLogic = require("./todo.js");

const { addTodo, toggleTodo, removeTodo, clearCompleted, filterTodos, activeCount } = TodoLogic;

test("addTodo appends a trimmed incomplete item", function () {
  const todos = [{ id: "1", text: "first", completed: false }];
  const result = addTodo(todos, "  hi  ", "2");

  assert.deepEqual(result, [
    { id: "1", text: "first", completed: false },
    { id: "2", text: "hi", completed: false }
  ]);
});

test("addTodo ignores whitespace-only text and keeps the same reference", function () {
  const todos = [{ id: "1", text: "first", completed: false }];

  const result = addTodo(todos, "   ", "2");

  assert.strictEqual(result, todos);
});

test("addTodo does not mutate the input array", function () {
  const todos = [{ id: "1", text: "first", completed: false }];
  const snapshot = structuredClone(todos);

  addTodo(todos, "second", "2");

  assert.deepEqual(todos, snapshot);
  assert.equal(todos.length, 1);
});

test("toggleTodo reverses only the target and keeps the input unchanged", function () {
  const first = { id: "1", text: "first", completed: false };
  const second = { id: "2", text: "second", completed: true };
  const todos = [first, second];

  const result = toggleTodo(todos, "1");

  assert.deepEqual(result, [
    { id: "1", text: "first", completed: true },
    second
  ]);
  assert.notStrictEqual(result, todos);
  assert.notStrictEqual(result[0], first);
  assert.strictEqual(result[1], second);
  assert.deepEqual(todos, [first, second]);
});

test("toggleTodo returns the same content for an unknown id", function () {
  const todos = [{ id: "1", text: "first", completed: false }];

  const result = toggleTodo(todos, "missing");

  assert.notStrictEqual(result, todos);
  assert.deepEqual(result, todos);
});

test("removeTodo removes the target without mutating the input", function () {
  const todos = [
    { id: "1", text: "first", completed: false },
    { id: "2", text: "second", completed: false }
  ];

  const result = removeTodo(todos, "1");

  assert.deepEqual(result, [{ id: "2", text: "second", completed: false }]);
  assert.deepEqual(todos, [
    { id: "1", text: "first", completed: false },
    { id: "2", text: "second", completed: false }
  ]);
});

test("clearCompleted removes all completed items", function () {
  const todos = [
    { id: "1", text: "active", completed: false },
    { id: "2", text: "done", completed: true },
    { id: "3", text: "also done", completed: true }
  ];

  assert.deepEqual(clearCompleted(todos), [
    { id: "1", text: "active", completed: false }
  ]);
});

test("filterTodos supports all, active, and completed", function () {
  const active = { id: "1", text: "active", completed: false };
  const completed = { id: "2", text: "done", completed: true };
  const todos = [active, completed];

  assert.deepEqual(filterTodos(todos, "all"), [active, completed]);
  assert.deepEqual(filterTodos(todos, "active"), [active]);
  assert.deepEqual(filterTodos(todos, "completed"), [completed]);
});

test("filterTodos treats an unknown filter as all", function () {
  const todos = [
    { id: "1", text: "active", completed: false },
    { id: "2", text: "done", completed: true }
  ];

  assert.deepEqual(filterTodos(todos, "unknown"), todos);
});

test("activeCount counts incomplete items and handles an empty array", function () {
  assert.equal(activeCount([]), 0);
  assert.equal(activeCount([
    { id: "1", text: "active", completed: false },
    { id: "2", text: "done", completed: true },
    { id: "3", text: "also active", completed: false }
  ]), 2);
});
