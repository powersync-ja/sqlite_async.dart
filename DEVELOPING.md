# Developing Instructions

## Testing

Running tests for the `web` platform requires some preparation to be executed. The `sqlite3.wasm` and `db_worker.js` files need to be available in the Git ignored `./assets` folder.

See the [test action](./.github/workflows/test.yaml) for the latest steps.

On your local machine run the commands from the `Install SQLite`, `Compile WebWorker` and `Run Tests` steps.
