const csv = require('csv-parser')
const fs = require('fs')

const taxonomy = {
    id: "BP-AOS-LIST22",
    species: []
};

const checklist = {
    id: "BP-AOS-LIST22/generic",
    species: []
}

function normalizeSciName(sciName) {
    let ret = sciName.replace(/  +/g, ' ');
    ret = ret.replace(/(\(.*)sp\./, '$1sp');
    ret = ret.replace(/(\(.*)gen\./, '$1gen');
    ret = ret.replace('(gen sp)', '(gen, sp)');
    ret = ret.replace(/ sp\.$/, ' (sp)');

    return ret;
}

function speciesType(SP, species) {
    if (!SP) return 'species';

    if (species.sciName.indexOf(' x ') != -1) {
        return 'hybrid';
    }
    if (species.sciName.match(/ hybrid$/) !== null) {
        return 'hybrid';
    }
    if (species.sciName.match(/\w+\/\w+/) !== null) {
        return 'splitting';
    }

    if (species.sciName.match(/ae$/) !== null) {
        return 'family';
    }

    if (species.sciSpeciesName.match(/ \(sp\)$/) != null) {
        return 'genus';
    }

    const nomial = species.sciName.split(' ').length;
    if( nomial == 3) {
        return 'subspecies';
    }

    if( species.sciName === 'Aves') {
        return 'class';
    }

    return 'unknown';
}

let order = 1;
function addSpecies(species) {
    let sp = {};
    const sciName = normalizeSciName(species.SCINAME);
    sp.id = sciName;
    sp.taxonomicOrder = order;
    sp.code = species.SPEC
    sp.sciSpeciesName = sciName
    sp.sciName = sciName.replace(/ *\(.*\)$/, '');
    sp.id = sp.sciName;
    sp.sciCode = species.SPEC6;
    sp.type = speciesType(species.SP, sp);
    if (sp.type == 'hybrid') {
        sp.components = sp.sciName.split(' x ');
        if (sp.components.length > 1) {
            const genus = sp.components[0].split(' ')[0]
            for(let i = 1 ; i < sp.components.length; i++) {
                sp.components[i] = `${genus} ${sp.components[i]}`;
            }
        } else {
            sp.components[0] = sp.components[0].replace(/ hybrid$/, ''); 
        }
    }
    if (sp.type == 'splitting') {
        sp.components = sp.sciName.split('/');
        if (sp.components.length > 1) {
            const genus = sp.components[0].split(' ')[0]
            for(let i = 1 ; i < sp.components.length; i++) {
                sp.components[i] = `${genus} ${sp.components[i]}`;
            }
        }
    }

    taxonomy.species.push(sp);

    let check = {};
    check.id = sciName;
    check.name = species.COMMONNAME;
    check.sortOrder = order;

    checklist.species.push(check);

    order++;
}

fs.createReadStream('IBP-AOS-LIST22.csv')
  .pipe(csv())
  .on('data', (data) => addSpecies(data))
  .on('end', () => {
    fs.writeFileSync('./taxonomy.json', JSON.stringify(taxonomy, null, 2))
    fs.writeFileSync('./checklist.json', JSON.stringify(checklist, null, 2))
  });