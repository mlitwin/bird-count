class Species {
  id: string;
  type: string;
  sciName: string;
  taxonomicOrder: number;
  localizations: object;
  parent: string;
}

class Taxonomy {
  id: string;
  species: Species[];

  speciesTaxons: { [id: string]: Species };
  constructor(id: string) {
    this.id = id;
    this.speciesTaxons = {};
  }
  addSpecies(species: Species[]) {
    this.species = species;

    this.species.forEach((sp) => {
      this.speciesTaxons[sp.id] = sp;
    });
  }
}

function addAbbeviations(species) {
  let abbrv = [];
  const commonName = species.localizations.en.commonName.toUpperCase();

  const name = commonName
    .replaceAll(/[^-A-Za-z /]/g, "")
    .replaceAll(/[^A-Za-z]/g, " ")
    .split(/\s+/)
    .map((w) => w[0])
    .join("");

  abbrv.push(name);
  species.abbreviations = abbrv;
}

function testFilter(sp) {
  switch (sp.type) {
    case "hybrid":
    case "slash":
    case "issf":
    case "intergrade":
    case "form":
      return false;
  }

  return true;
}

class Checklist {
  taxonomy: Taxonomy;

  species: Species[];

  constructor(taxonomy: Taxonomy) {
    this.taxonomy = taxonomy;
    this.species = [];
  }

  setFilters(filters: any) {
    for (let id in filters.species) {
      const sp = filters.species[id];
      const tax = this.taxonomy.speciesTaxons[id];
      let chsp = { ...tax, ...sp };
      chsp.standard = testFilter(chsp);
      addAbbeviations(chsp);
      this.species.push(chsp);
    }
  }
}

class Observation {
  id: string;
  createdAt: number;
  start: number;
  duration: number;
  species: any;
  count: number;
  parent: null | Observation;
  children?: Observation[];

  toJSONObject(): object {
    return {
      id: this.id,
      createdAt: this.createdAt,
      start: this.start,
      duration: this.duration,
      species: this.species.id,
      count: this.count,
      parent: this.parent ? this.parent.id : null,
    };
  }

  fromJSONObject(taxonomy: Taxonomy, json: any) {
    this.id = json.id;
    this.createdAt = json.createdAt;
    this.start = json.start;
    this.duration = json.duration;
    this.species = taxonomy.speciesTaxons[json.species];
    this.count = json.count;
    this.parent = null;
  }
}

class ObservationSet extends Observation {
  constructor(obs: Observation[]) {
    super();
    this.setObservations(obs);
  }
  setObservations(obs: Observation[]) {
    this.observations = obs;
  }
  observations: Observation[];
}

export { ObservationSet, Observation, Species, Taxonomy, Checklist };
