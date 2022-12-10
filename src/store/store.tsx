import { useEffect, useState } from 'react'
import { bind } from '@react-rxjs/core'
import { createSignal } from '@react-rxjs/utils'
import {
    Observation,
    Taxonomy,
    Checklist,
    Species,
    ObservationSet,
} from '../model/types'

import taxonomyJSON from '../data/taxonomy.json'
import chk from '../data/checklist.json'

class ObservationContext {
    constructor() {
        this.taxonomy = null
        this.checklist = null
    }
    ready() {
        return this.taxonomy != null && this.checklist != null
    }
    taxonomy: Taxonomy
    checklist: Checklist
}

function useObservationContext() {
    const [observationContext, setObservationContext] =
        useState<ObservationContext>(new ObservationContext())

    useEffect(() => {
        const oc = new ObservationContext()
        oc.taxonomy = new Taxonomy((taxonomyJSON as any).id)
        oc.taxonomy.addSpecies((taxonomyJSON as any).species as Species[])
        oc.checklist = new Checklist(oc.taxonomy)
        oc.checklist.setFilters(chk)
        setObservationContext(oc)
        try {
            const storage = window.localStorage.getItem('observations')
            if (storage) {
                const newList = deserializeObservations(
                    oc.taxonomy,
                    JSON.parse(storage)
                )
                setObservationList(newList)
                setRecentObservationList(computeRecentObservations(newList))
            }
        } catch (e) {}
    }, [])

    return observationContext
}

const [observationListChange$, setObservationList] =
    createSignal<Observation[]>()
const [observations, observations$] = bind<Observation[]>(
    observationListChange$,
    []
)

observations$.subscribe(() => {})

const [observationAdded$, signalAddedObservation] = createSignal<Observation>()

observationAdded$.subscribe((obs) => {})

function addObservation(
    curObservations: Observation[],
    newObservation: Observation
) {
    const newList = curObservations.map((obs) => {
        if (newObservation.parent) {
            if (obs.id === newObservation.parent.id) {
                const o = new Observation()
                o.Assign(obs)
                o.children = obs.children
                if (!o.children) {
                    o.children = []
                }
                o.children.push(newObservation)
                return o
            }
        }
        return obs
    })

    newList.push(newObservation)

    window.localStorage.setItem(
        'observations',
        JSON.stringify(serializeObservations(newList))
    )
    setObservationList(newList)
    setRecentObservationList(computeRecentObservations(newList))
    signalAddedObservation(newObservation)
}

function useAddObservation() {
    const currentObservations = observations()
    return (obs: Observation) => {
        addObservation(currentObservations, obs)
    }
}

const [recentObservationListChange$, setRecentObservationList] =
    createSignal<Observation[]>()
observationListChange$.subscribe(() => {})

const [recentObservations, recentObservations$] = bind<any>(
    recentObservationListChange$,
    []
)
recentObservations$.subscribe(() => {})

function clearObservations() {
    window.localStorage.removeItem('observations')
    setObservationList([])
}

function serializeObservations(obsList: Observation[]) {
    const l = []
    obsList.forEach((obs) => {
        l.push(obs.toJSONObject())
    })
    return l
}

function deserializeObservations(taxonomy: Taxonomy, json: any): Observation[] {
    const l: Observation[] = []
    const lById: { [id: string]: Observation } = {}
    const jById: { [id: string]: any } = {}
    json.forEach((o) => {
        let obs = new Observation()
        obs.fromJSONObject(taxonomy, o)
        l.push(obs)
        lById[obs.id] = obs
        jById[o.id] = o
    })
    l.forEach((obs) => {
        const parentId = jById[obs.id].parent
        if (parentId) {
            const parent = lById[parentId]
            obs.parent = parent
            if (!parent.children) {
                parent.children = []
            }
            parent.children.push(obs)
        }
    })
    return l
}

function computeRecentObservations(list: Observation[], now?: number) {
    if (!now) {
        now = Date.now()
    }
    const day = 24 * 60 * 60 * 1000
    const recentList = list
        .filter((obs) => obs.createdAt >= now - day)
        .sort((a, b) => b.createdAt - a.createdAt)

    return recentList
}

export {
    useAddObservation,
    observations,
    recentObservations,
    clearObservations,
    useObservationContext,
}
