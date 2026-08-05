(function () {
  "use strict";

  var STORAGE_KEY = "todo-app.v1";
  var form = document.getElementById("new-todo-form");
  var input = document.getElementById("new-todo-input");
  var filters = document.getElementById("filters");
  var todoList = document.getElementById("todo-list");
  var emptyState = document.getElementById("empty-state");
  var itemsLeft = document.getElementById("items-left");
  var clearCompletedButton = document.getElementById("clear-completed");

  function loadTodos() {
    try {
      var stored = window.localStorage.getItem(STORAGE_KEY);
      if (!stored) {
        return [];
      }

      var parsed = JSON.parse(stored);
      if (!parsed || !Array.isArray(parsed.todos)) {
        return [];
      }

      return parsed.todos;
    } catch (error) {
      return [];
    }
  }

  function save() {
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify({ todos: state.todos }));
    } catch (error) {
      return;
    }
  }

  function createId() {
    try {
      return crypto.randomUUID();
    } catch (error) {
      return Date.now().toString(36) + Math.random().toString(36).slice(2);
    }
  }

  var state = { todos: loadTodos(), filter: "all" };

  function updateTodos(todos) {
    state.todos = todos;
    render();
    save();
  }

  function render() {
    var visibleTodos = TodoLogic.filterTodos(state.todos, state.filter);
    todoList.textContent = "";

    visibleTodos.forEach(function (todo) {
      var item = document.createElement("li");
      item.className = "todo-item";
      item.setAttribute("data-id", todo.id);
      if (todo.completed) {
        item.classList.add("completed");
      }

      var checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.className = "todo-check";
      checkbox.checked = todo.completed;
      checkbox.setAttribute("aria-label", "완료 표시");

      var text = document.createElement("span");
      text.className = "todo-text";
      text.textContent = todo.text;

      var deleteButton = document.createElement("button");
      deleteButton.type = "button";
      deleteButton.className = "todo-delete";
      deleteButton.setAttribute("aria-label", todo.text + " 삭제");
      deleteButton.textContent = "×";

      item.appendChild(checkbox);
      item.appendChild(text);
      item.appendChild(deleteButton);
      todoList.appendChild(item);
    });

    emptyState.hidden = visibleTodos.length !== 0;
    itemsLeft.textContent = `${TodoLogic.activeCount(state.todos)}개 남음`;
    clearCompletedButton.disabled = !state.todos.some(function (todo) {
      return todo.completed === true;
    });

    filters.querySelectorAll("[data-filter]").forEach(function (button) {
      button.setAttribute("aria-pressed", button.getAttribute("data-filter") === state.filter ? "true" : "false");
    });
  }

  form.addEventListener("submit", function (event) {
    event.preventDefault();
    updateTodos(TodoLogic.addTodo(state.todos, input.value, createId()));
    input.value = "";
    input.focus();
  });

  todoList.addEventListener("change", function (event) {
    if (!event.target.matches(".todo-check")) {
      return;
    }

    var item = event.target.closest(".todo-item");
    if (!item) {
      return;
    }

    updateTodos(TodoLogic.toggleTodo(state.todos, item.getAttribute("data-id")));
  });

  todoList.addEventListener("click", function (event) {
    var deleteButton = event.target.closest(".todo-delete");
    if (!deleteButton) {
      return;
    }

    var item = deleteButton.closest(".todo-item");
    if (!item) {
      return;
    }

    updateTodos(TodoLogic.removeTodo(state.todos, item.getAttribute("data-id")));
  });

  filters.addEventListener("click", function (event) {
    var button = event.target.closest("[data-filter]");
    if (!button || !filters.contains(button)) {
      return;
    }

    var filter = button.getAttribute("data-filter");
    if (filter !== "all" && filter !== "active" && filter !== "completed") {
      filter = "all";
    }

    state.filter = filter;
    render();
    save();
  });

  clearCompletedButton.addEventListener("click", function () {
    updateTodos(TodoLogic.clearCompleted(state.todos));
  });

  render();
})();
