import * as fs from "fs/promises";

async function readJSON(filename) {
  const data = await fs.readFile(filename);
  return JSON.parse(data);
}

const all = await readJSON("all.json");
const then = 1717774857000;
const ob = all.filter((a) => a.createdAt >= then);

console.log(ob);
