const fs = require('fs');
const cheerio = require('cheerio');
const html = fs.readFileSync('speclist.cfm');
const $ = cheerio.load(html);
const elems = $('#spectbl tbody tr td');

const cols = [
    "", // Species Numbe
    "code", // Alpha Code
    "name", // Common Name
    "", // Band Size
    "", // French Name
    "sname", // Scientific Name
    "", // title
    "", // Comments
    "taxonomicOrder" // Taxonomic Order
];

let elem = {};

let list = [];

elems.each((i,e) => {
    const index = i % cols.length;

    const k = cols[index]
    if( k) {
        const t = $(e).text();
        elem[k] = t
      //  console.log(`${k}: ${t}`);
    }
    if (index == cols.length -1) {
        list.push(elem);
        elem = {};
    }
});

console.log(JSON.stringify(list, null, 2));


