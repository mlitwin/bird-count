import * as React from 'react'
import IconButton from '@mui/material/IconButton'
import MenuItem from '@mui/material/MenuItem'
import Menu from '@mui/material/Menu'
import { MoreHoriz } from '@mui/icons-material'

const options = ['Cancel', 'Delete']

export default function MoreMenu(props) {
    const [anchorEl, setAnchorEl] = React.useState<null | HTMLElement>(null)
    const [selectedIndex, setSelectedIndex] = React.useState(1)
    const open = Boolean(anchorEl)
    const handleClickListItem = (event: React.MouseEvent<HTMLElement>) => {
        setAnchorEl(event.currentTarget)
    }

    const handleMenuItemClick = (
        event: React.MouseEvent<HTMLElement>,
        index: number
    ) => {
        setSelectedIndex(index)
        setAnchorEl(null)
        switch (index) {
            case 0:
                props.doCancel()
                break
        }
    }

    const handleClose = () => {
        setAnchorEl(null)
    }

    return (
        <div>
            <IconButton onClick={handleClickListItem}>
                <MoreHoriz fontSize="large" />
            </IconButton>
            <Menu
                id="lock-menu"
                anchorEl={anchorEl}
                open={open}
                onClose={handleClose}
                MenuListProps={{
                    'aria-labelledby': 'lock-button',
                    role: 'listbox',
                }}
            >
                {options.map((option, index) => (
                    <MenuItem
                        key={option}
                        selected={index === selectedIndex}
                        onClick={(event) => handleMenuItemClick(event, index)}
                    >
                        {option}
                    </MenuItem>
                ))}
            </Menu>
        </div>
    )
}
