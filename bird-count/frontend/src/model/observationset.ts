import Observation from './observation'

class ObservationSet extends Observation {
    constructor(obs: Observation[]) {
        super()
        this.setObservations(obs)
    }
    setObservations(obs: Observation[]) {
        this.observations = []
        obs.forEach((o, index) => {
            const UnionWithDescendents = (parent: Observation) => {
                if (parent.children) {
                    parent.children.forEach((child) => {
                        this.UnionWithDescendent(child)
                        UnionWithDescendents(child)
                    })
                }
            }
            if (index === 0) {
                this.Assign(o)
            } else {
                this.Union(this.taxonomy, o)
            }
            UnionWithDescendents(o)
            this.observations.push(o)
        })
    }
    observations: Observation[]
    newObservationParent(): Observation | null {
        if (this.observations.length === 1) {
            return this.observations[0]
        }
        return null
    }
}

export default ObservationSet
