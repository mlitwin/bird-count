import React from 'react'
import Dialog from '@mui/material/Dialog'
import AppBar from '@mui/material/AppBar'
import Toolbar from '@mui/material/Toolbar'
import Button from '@mui/material/Button'
import IconButton from '@mui/material/IconButton'
import Link from '@mui/material/Link'
import CloseIcon from '@mui/icons-material/Close'

import Slider from '@mui/material/Slider'

import { observations, clearObservations } from './store/store'

import './Settings.css'

function Settings(props) {
    const allObservations = observations()
    const observationsJSON = allObservations.map((o) => o.toJSONObject())
    const mail = encodeURIComponent(JSON.stringify(observationsJSON, null, 2))
    const mailto = `mailto:?body=${mail}&subject=Email the List`

    const marks = [
        { value: 0, label: 'Never' },
        { value: 1, label: 'Scarce' },
        { value: 2, label: 'Uncommon' },
        { value: 3, label: 'Common' },
    ]
    function handleClose() {
        props.setOpen(false)
    }
    function handleChange(_e, value) {
        props.setCommonnessSetting(3 - value)
    }

    return (
        <Dialog fullScreen open={props.open}>
            <AppBar sx={{ position: 'relative' }}>
                <Toolbar>
                    <IconButton
                        edge="start"
                        color="inherit"
                        onClick={handleClose}
                        aria-label="close"
                    >
                        <CloseIcon />
                    </IconButton>
                </Toolbar>
            </AppBar>
            <div className="SettingsContent">
                <div className="Commonness">
                    <Slider
                        defaultValue={0}
                        value={3 - props.commonnessSetting}
                        onChange={handleChange}
                        valueLabelDisplay="off"
                        marks={marks}
                        min={0}
                        max={3}
                    />
                </div>
                <div className="SettingsButtons">
                    <Link component="a" href={mailto} variant="button">
                        Email Observations
                    </Link>
                    <Button
                        variant="contained"
                        onClick={(e) => clearObservations()}
                    >
                        CLEAR
                    </Button>
                </div>
            </div>
        </Dialog>
    )
}

export default Settings
