import React, { useState } from 'react'
import { AdapterDayjs } from '@mui/x-date-pickers/AdapterDayjs'
import { LocalizationProvider } from '@mui/x-date-pickers'
import { DateTimePicker } from '@mui/x-date-pickers'
import TextField from '@mui/material/TextField'
import Button from '@mui/material/Button'
import { IconButton } from '@mui/material'
import {
    NavigateBeforeOutlined,
    NavigateNextOutlined,
    EmailOutlined,
} from '@mui/icons-material'

import { Taxonomy, Observation, ObservationSet } from 'model/types'
import ObservationEntry from './common/ObservationEntry'
import List from '@mui/material/List'
import ListItem from '@mui/material/ListItem'
import { getAppContext } from './store/store'

import { observations } from './store/store'

import dayjs from 'dayjs'

import './ObservationSummary.css'

function filterObservations(obs: Observation[], start, end) {
    return obs.filter(
        (o) =>
            o.parent === null && o.start >= start && o.start + o.duration <= end
    )
}

function computeSummary(
    obs: Observation[]
): [null | ObservationSet, ObservationSet[]] {
    const ac = getAppContext()

    const obsBySpecies: { [key: string]: ObservationSet } = {}
    let summary = null

    obs.forEach((obs) => {
        const sp = ac.taxonomy.speciesTaxon(obs.species)
        if (!obsBySpecies[sp.id]) {
            obsBySpecies[sp.id] = new ObservationSet([obs])
        } else {
            obsBySpecies[sp.id].Union(ac.taxonomy, obs)
        }
    })

    const obsSummaries: ObservationSet[] = []
    for (let k in obsBySpecies) {
        const obs = obsBySpecies[k]
        obsSummaries.push(obs)
        if (summary === null) {
            summary = new ObservationSet([obs])
        } else {
            summary.Union(ac.taxonomy, obs)
        }
    }

    obsSummaries.sort(
        (a, b) => a.species.taxonomicOrder - b.species.taxonomicOrder
    )

    return [summary, obsSummaries]
}

function SummaryListHeader(props) {
    if (null === props.summary) {
        return <div className="SummaryListHeader">No observations</div>
    }
    return (
        <div className="SummaryListHeader">
            <ObservationEntry
                initialMode="display"
                variant="header"
                observation={props.summary}
                displaySummary={props.statistics}
                isScrolling={false}
            ></ObservationEntry>
        </div>
    )
}

function countSpecies(taxonomy: Taxonomy, observations: Observation[]): number {
    let ret = 0

    const counted: { [id: string]: Boolean } = {}

    observations.forEach((obs) => {
        let t = obs.species.id
        if (!counted[t]) {
            ret++
            while (t && !counted[t]) {
                counted[t] = true
                t = taxonomy.speciesTaxons[t].parent
            }
        }
    })
    return ret
}

function ObservationSummary() {
    const ac = getAppContext()

    const now = dayjs()
    const today = now.startOf('day')
    const tomorrow = now.endOf('day')

    const allObservations = observations()

    const [start, setStart] = useState(today)
    const [end, setEnd] = useState(tomorrow)

    const obs = filterObservations(allObservations, start, end)
    const [summary, obsSummaries] = computeSummary(obs)

    const speciesCount = countSpecies(ac.taxonomy, obs)
    const statistics = `${speciesCount} species`

    const dateRangeString = `${start.format(
        'ddd MM/D/YY hh:mm a'
    )} - ${end.format('ddd MM/D/YY hh:mm a')}`

    const textExport = obsSummaries
        .map((o) => `${o.count} ${o.species.localizations.en.commonName}`)
        .join('\n')
    const textExportSummary = `${dateRangeString} ${statistics}\n\n`

    const mailto = `mailto:?body=${encodeURIComponent(
        textExportSummary + textExport
    )}&subject=Email the Summary`

    function goToToday() {
        const now = dayjs()
        const today = now.startOf('day')
        const tomorrow = now.endOf('day')
        setStart(today)
        setEnd(tomorrow)
    }
    function deltaByDay(days) {
        setStart(start.add(days, 'days'))
        setEnd(end.add(days, 'days'))
    }

    return (
        <div className="ObservationHistorySummary oneColumn">
            <div className="Controls">
                <div className="DateRangePicker">
                    <LocalizationProvider dateAdapter={AdapterDayjs}>
                        <div>
                            <DateTimePicker
                                renderInput={(props) => (
                                    <TextField {...props} />
                                )}
                                label="Start"
                                hideTabs={false}
                                value={start}
                                onChange={(newValue) => {
                                    setStart(newValue)
                                }}
                            />
                        </div>

                        <div>
                            <DateTimePicker
                                renderInput={(props) => (
                                    <TextField {...props} />
                                )}
                                label="End"
                                hideTabs={false}
                                value={end}
                                onChange={(newValue) => {
                                    setEnd(newValue)
                                }}
                            />
                        </div>
                    </LocalizationProvider>
                </div>
                <div className="DateRangeNavigator">
                    <IconButton onClick={() => deltaByDay(-1)}>
                        <NavigateBeforeOutlined />
                    </IconButton>
                    <Button onClick={goToToday}>Today</Button>
                    <IconButton onClick={() => deltaByDay(1)}>
                        <NavigateNextOutlined />
                    </IconButton>
                </div>
                <div className="DateRangeActions">
                    <a href={mailto}>
                        <EmailOutlined />
                    </a>
                </div>
            </div>
            <SummaryListHeader
                summary={summary}
                statistics={statistics}
            ></SummaryListHeader>
            <div className="oneColumnExpand">
                <div className="ObvservationSummaryList">
                    <List>
                        {obsSummaries.map((obs) => (
                            <ListItem key={obs.id} disableGutters={true}>
                                <ObservationEntry
                                    initialMode="display"
                                    variant="entry"
                                    observation={obs}
                                    isScrolling={false}
                                ></ObservationEntry>
                            </ListItem>
                        ))}
                    </List>
                </div>
            </div>
        </div>
    )
}

export default ObservationSummary
