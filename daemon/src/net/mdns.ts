// mDNS advertise for _werkz._tcp (task 6 §3). Convenience only — the QR is the
// source of truth for pairing. Best-effort: if bonjour-service isn't present
// or multicast fails, we log and continue. Never fatal.

export interface MdnsHandle {
  stop: () => void;
}

interface BonjourInstance {
  publish: (o: object) => { stop: (cb?: () => void) => void };
  destroy: () => void;
}

export async function advertise(port: number, name = 'Werkz Workshop'): Promise<MdnsHandle> {
  try {
    const mod = (await import('bonjour-service')) as unknown as {
      Bonjour?: new () => BonjourInstance;
      default?: new () => BonjourInstance;
    };
    const Bonjour = mod.Bonjour ?? mod.default;
    if (!Bonjour) throw new Error('bonjour-service shape unexpected');
    const instance = new Bonjour();
    const service = instance.publish({ name, type: 'werkz', protocol: 'tcp', port });
    return {
      stop: () => {
        try { service.stop(); instance.destroy(); } catch { /* ignore */ }
      },
    };
  } catch (err) {
    console.log(`  (mDNS advertise unavailable — pairing still works via QR: ${(err as Error).message})`);
    return { stop: () => {} };
  }
}
