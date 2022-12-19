const fs = require('fs')
const Ajv2020 = require("ajv/dist/2020")
const { exit } = require('process')
const ajv = new Ajv2020() // options can be passed, e.g. {allErrors: true}


const taxonomySchema = JSON.parse(fs.readFileSync('./schemas/taxonomy.json'))

const validate = ajv.compile(taxonomySchema)


const taxonomy = JSON.parse(fs.readFileSync('./taxonomy.json'))

let valid = validate(taxonomy)
if (!valid) console.log(validate.errors)

const speciesById = {};
const childrendById = {};
const sciNames = {};

taxonomy.species.forEach(sp => {
    const id = sp.id;

    if( speciesById[id]) {
        valid = false;
        console.log(`Duplicate species id ${id}`)
    }
    const sciName = sp.sciName;
    sciNames[sciName] = true;

    speciesById[id] = sp;
    childrendById[id] = [];
});

taxonomy.species.forEach(sp => {
    const parent = sp.parent;

    if(parent) {
        childrendById[parent].push(sp.id); 
    }

    if( sp.id !== 'bird1' && !speciesById[parent]) {
        valid = false;
        console.log(`Parent not found for ${JSON.stringify(sp)} seeking ${parent}`)
    }

    if( sp.id === sp.parent) {
        console.log(sp)
    }
});


const visited = {};

function visit(sp) {
    if (visited[sp]) {
        valid = false;
        console.log(`Circularity detected at ${sp}`);    
        exit(0)  
    }
    visited[sp] = true;
    childrendById[sp].forEach(v => visit(v)); 
}

visit('bird1');

const visitCount = Object.keys(visited).length;

if( visitCount !== taxonomy.species.length) {
    valid = false;
    console.log("Not all species descend from Aves");
    taxonomy.species.forEach(sp => {
        const id = sp.id;
        if (!visited[id]) {
            console.log(sp.id);
        }
    });
}

if (!valid) {
    exit(-1)
}
