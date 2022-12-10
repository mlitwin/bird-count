import Taxonomy from "./taxonomy";

class Observation {
  id: string;
  createdAt: number;
  start: number;
  duration: number;
  taxonomy: Taxonomy;
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
      taxonomy: this.taxonomy.id,
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
    this.taxonomy = taxonomy;
    this.species = taxonomy.speciesTaxons[json.species];
    this.count = json.count;
    this.parent = null;
  }

  Assign(obs: Observation) {
    this.id = obs.id;
    this.createdAt = obs.createdAt;
    this.start = obs.start;
    this.duration = obs.duration;
    this.taxonomy = obs.taxonomy;
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

export default Observation;
