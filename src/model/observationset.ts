import Taxonomy from "./taxonomy";
import Observation from "./observation";

class ObservationSet extends Observation {
  taxonomy: Taxonomy;
  constructor(taxonomy: Taxonomy, obs: Observation[]) {
    super();
    this.taxonomy = taxonomy;
    this.setObservations(obs);
  }
  setObservations(obs: Observation[]) {
    this.observations = [];
    obs.forEach((o, index) => {
      const UnionWithDescendents = (parent: Observation) => {
        if (parent.children) {
          parent.children.forEach((child) => {
            this.UnionWithDescendent(child);
            UnionWithDescendents(child);
          });
        }
      };
      if (index === 0) {
        this.Assign(o);
      } else {
        this.Union(this.taxonomy, o);
      }
      UnionWithDescendents(o);
      this.observations.push(o);
    });
  }
  observations: Observation[];
}

export default ObservationSet;
