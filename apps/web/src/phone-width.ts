import { useEffect, useState } from 'react';

/** #510: the width below which the shell drops secondary chrome (phone-declutter.css). */
export const PHONE_DECLUTTER_QUERY = '(max-width: 767px)';

/** Whether the viewport is at phone width, tracking changes (rotation, resize). */
export function usePhoneWidth(): boolean {
  const [phone, setPhone] = useState(() => typeof window !== 'undefined' && typeof window.matchMedia === 'function' && window.matchMedia(PHONE_DECLUTTER_QUERY).matches);
  useEffect(() => {
    if (typeof window.matchMedia !== 'function') return;
    const query = window.matchMedia(PHONE_DECLUTTER_QUERY);
    const change = () => setPhone(query.matches);
    change();
    query.addEventListener('change', change);
    return () => query.removeEventListener('change', change);
  }, []);
  return phone;
}
