(function (global) {
  "use strict";

  function addTodo(todos, text, id) {
    var trimmed = text.trim();
    if (trimmed === "") {
      return todos;
    }

    return todos.concat({ id: id, text: trimmed, completed: false });
  }

  function toggleTodo(todos, id) {
    return todos.map(function (todo) {
      if (todo.id === id) {
        return Object.assign({}, todo, { completed: !todo.completed });
      }
      return todo;
    });
  }

  function removeTodo(todos, id) {
    return todos.filter(function (todo) {
      return todo.id !== id;
    });
  }

  function clearCompleted(todos) {
    return todos.filter(function (todo) {
      return todo.completed === false;
    });
  }

  function filterTodos(todos, filter) {
    if (filter === "active") {
      return todos.filter(function (todo) {
        return todo.completed === false;
      });
    }

    if (filter === "completed") {
      return todos.filter(function (todo) {
        return todo.completed === true;
      });
    }

    return todos.slice();
  }

  function activeCount(todos) {
    return todos.reduce(function (count, todo) {
      return todo.completed === false ? count + 1 : count;
    }, 0);
  }

  var TodoLogic = { addTodo: addTodo, toggleTodo: toggleTodo, removeTodo: removeTodo, clearCompleted: clearCompleted, filterTodos: filterTodos, activeCount: activeCount };
  if (typeof module !== "undefined" && module.exports) { module.exports = TodoLogic; }
  else { global.TodoLogic = TodoLogic; }
})(globalThis);
