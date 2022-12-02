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

  commonAncestor(a: Species, b: Species): Species {
    let o = a;
    const marked = {};
    while(o) {
      marked[o.id] = true;
      o = this.speciesTaxons[o.parent];
    }
    o = b;
    while(o) {
     if(marked[o.id]) {
      return o;
     }
     o = this.speciesTaxons[o.parent];
    }
    // notreached
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

  Assign(obs: Observation) {
    this.id = obs.id;
    this.createdAt = obs.createdAt;
    this.start = obs.start;
    this.duration = obs.duration;
    this.species = obs.species;
    this.count = obs.count;
    this.parent = obs.parent;
  }

  Union(taxonomy: Taxonomy, obs: Observation) {
    const thisend = this.start + this.duration;
    const thatend = obs.start + obs.duration;
    if (obs.start < this.start) {
      this.start = obs.start;
    }
    const end = thisend > thatend ? thisend : thatend;
    this.duration = end - this.start;
    this.species = taxonomy.commonAncestor(this.species, obs.species);
    this.count += obs.count;
  }

  UnionWithDescendent(obs: Observation) {
    this.count += obs.count;
  }
}

class ObservationSet extends Observation {
  taxonomy: Taxonomy;
  constructor(taxonomy: Taxonomy, obs: Observation[]) {
    super();
    this.taxonomy = taxonomy;
    this.setObservations(obs);
  }
  setObservations(obs: Observation[]) {
    this.observations = obs;
    obs.forEach((obs, index) => {
      const UnionWithDescendents = (parent: Observation) => {
        if(parent.children) {
          parent.children.forEach((child)=> {
            this.UnionWithDescendent(child);
            UnionWithDescendents(child)
          });
        }
      }
      if(index === 0) {
        this.Assign(obs);
      } else {
        this.Union(this.taxonomy, obs);
      }
      UnionWithDescendents(obs);
    });
  }
  observations: Observation[];
}

export { ObservationSet, Observation, Species, Taxonomy, Checklist };
