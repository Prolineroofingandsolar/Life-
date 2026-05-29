import { useState } from 'react'
import { Bell, Droplets, UtensilsCrossed, Timer, Wind } from 'lucide-react'
import { useLife } from '../lib/store'
import { LargeTitleHeader, SectionLabel, ListGroup, ListRow, Switch, Stepper } from '../components/ui'
import {
  notificationPermission,
  notificationsSupported,
  requestNotifications,
  notify,
} from '../lib/notifications'

export default function Body() {
  const { state, setCareSettings } = useLife()
  const cs = state.careSettings
  const [perm, setPerm] = useState(notificationPermission())

  const enableReminders = async () => {
    const p = await requestNotifications()
    setPerm(p)
    if (p === 'granted') {
      setCareSettings({ remindersEnabled: true })
      notify('Reminders on', 'I’ll nudge you to drink, eat and take breaks.')
    }
  }

  return (
    <div>
      <LargeTitleHeader title="Body" />
      <p className="-mt-1 mb-2 text-subhead text-label2">Because hyperfocus makes you forget the basics.</p>

      <SectionLabel>Reminders</SectionLabel>
      {!notificationsSupported() ? (
        <ListGroup>
          <ListRow icon={Bell} iconColor="rgb(var(--accent))" title="Not supported" subtitle="This browser can’t show notifications." />
        </ListGroup>
      ) : perm === 'granted' ? (
        <ListGroup>
          <ListRow
            icon={Bell}
            iconColor="rgb(var(--accent))"
            title="Nudges"
            subtitle="Water, meals & breaks while the app is open"
            trailing={<Switch checked={cs.remindersEnabled} onChange={(v) => setCareSettings({ remindersEnabled: v })} />}
          />
        </ListGroup>
      ) : (
        <ListGroup>
          <ListRow
            icon={Bell}
            iconColor="rgb(var(--accent))"
            title={<span className="text-accent">Enable reminders</span>}
            subtitle="Let Life nudge you to drink, eat & step away"
            onClick={enableReminders}
          />
        </ListGroup>
      )}
      <p className="ml-4 mt-2 text-footnote text-label2">On iPhone, add Life to your Home Screen first, then enable.</p>

      <SectionLabel>Daily goals</SectionLabel>
      <ListGroup>
        <ListRow
          icon={Droplets}
          iconColor="#32ade6"
          title="Water"
          trailing={
            <div className="flex items-center gap-3">
              <span className="tabular w-16 text-right text-body text-label2">{cs.waterGoal} glasses</span>
              <Stepper value={cs.waterGoal} onChange={(v) => setCareSettings({ waterGoal: v })} />
            </div>
          }
        />
        <ListRow
          icon={UtensilsCrossed}
          iconColor="#ff9f0a"
          title="Meals"
          trailing={
            <div className="flex items-center gap-3">
              <span className="tabular w-16 text-right text-body text-label2">{cs.mealsGoal} meals</span>
              <Stepper value={cs.mealsGoal} onChange={(v) => setCareSettings({ mealsGoal: v })} />
            </div>
          }
        />
      </ListGroup>

      <SectionLabel>Reminder timing</SectionLabel>
      <ListGroup>
        <ListRow
          icon={Timer}
          iconColor="#32ade6"
          title="Water every"
          trailing={
            <div className="flex items-center gap-3">
              <span className="tabular w-14 text-right text-body text-label2">{cs.waterIntervalMin} min</span>
              <Stepper value={cs.waterIntervalMin} step={15} min={15} onChange={(v) => setCareSettings({ waterIntervalMin: v })} />
            </div>
          }
        />
        <ListRow
          icon={Wind}
          iconColor="#30d158"
          title="Break every"
          trailing={
            <div className="flex items-center gap-3">
              <span className="tabular w-14 text-right text-body text-label2">{cs.breakIntervalMin} min</span>
              <Stepper value={cs.breakIntervalMin} step={10} min={20} onChange={(v) => setCareSettings({ breakIntervalMin: v })} />
            </div>
          }
        />
      </ListGroup>
    </div>
  )
}
