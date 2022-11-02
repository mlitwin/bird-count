const csv = require("csv-parser");
const fs = require("fs");
const { exit } = require("process");

const taxonomy = {
  id: "ebird_taxonomy_v2022",
  species: [],
};

const checklist = {
  id: "ebird_taxonomy_v2022:default",
  taxonomy: "ebird_taxonomy_v2022",
  species: {},
};

const CA = JSON.parse(fs.readFileSync('./eBird/CA.json'));
CA.forEach(code => {
    checklist.species[code] = {
        reportable: true,
      };
});

const bySciName = {};

function normalizeSciName(sciName) {
  return sciName.replace(/ sp\.$/, "");
}

function normalizeFamily(sciName) {
  return sciName.replace(/ .*$/, "");
}

function updateTypeToTaxon(sp) {
  if (sp.sciName === "Aves") {
    sp.type = "class";
  }
  if (sp.sciName === sp.family) {
    sp.type = "family";
  } else if (sp.sciName === sp.order) {
    sp.type = "order";
  } else {
    const binomial = sp.sciName.split(" ");
    if (sp.type === "spuh" && binomial.length === 1) {
      sp.type = "genus";
    }
  }
}

function addSpecies(s) {
  let sp = {};
  sp.id = s.SPECIES_CODE;
  sp.type = s.CATEGORY;
  sp.sciName = normalizeSciName(s.SCI_NAME);
  sp.taxonomicOrder = parseInt(s["﻿TAXON_ORDER"], 10);
  sp.localizations = {
    en: {
      commonName: s.PRIMARY_COM_NAME,
      group: s.SPECIES_GROUP,
    },
  };
  sp.order = s.ORDER1;
  sp.family = normalizeFamily(s.FAMILY);
  updateTypeToTaxon(sp);
  taxonomy.species.push(sp);

  bySciName[sp.sciName] = sp;
}

function getParentSciName(sp) {
  if (sp.sciName === "Aves") {
    return [null, null];
  }
  switch (sp.type) {
    case "order":
      return ["Aves", "class"];
    case "family":
      return [sp.order, "order"];
    case "genus":
      return [sp.family, "family"];
    default: {
      const binomial = sp.sciName.split(" ");
      return [binomial[0], "genus"];
    }
  }
}

function createTaxon(sciName, type, sp) {
  const t = {};
  t.id = sciName;
  t.type = type;
  t.sciName = sciName;
  t.localizations = {
    en: {
      commonName: sciName,
      group: sciName,
    },
  };

  t.order = sp.order;
  t.family = sp.family;

  return t;
}



fs.createReadStream("./eBird/ebird_taxonomy_v2022.csv")
  .pipe(csv())
  .on("data", (data) => addSpecies(data))
  .on("end", () => {
    for (let i = taxonomy.species.length - 1; i >= 0; i--) {
      const sp = taxonomy.species[i];
      const [parentSciName, parentType] = getParentSciName(sp);
      if (!parentSciName) {
        continue;
      }
      if (!bySciName[parentSciName]) {
        const parent = createTaxon(parentSciName, parentType, sp);
        bySciName[parentSciName] = parent;
        taxonomy.species.splice(i + 1, 0, parent);
        i += 2;
      }
      sp.parent = bySciName[parentSciName].id;
    }
    taxonomy.species.forEach((sp, index) => {
      sp.taxonomicOrder = index + 1;
      delete sp.order;
      delete sp.family;
    });

    fs.writeFileSync("./taxonomy.json", JSON.stringify(taxonomy, null, 2));
    fs.writeFileSync("./checklist.json", JSON.stringify(checklist, null, 2));
  });
