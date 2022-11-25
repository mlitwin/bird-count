class Observation {
  id: string;
  createdAt: number;
  start: number;
  duration: number;
  species: any;
  count: number;
  parent: string | null | Observation
}

type Species = any;

export { Observation, Species };
