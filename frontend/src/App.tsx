import { useState } from 'react';
import { useAccount, useConnect, useDisconnect, useReadContract } from 'wagmi';
import { injected } from 'wagmi/connectors';
import { Activity, Zap, TrendingUp, Wallet, Github } from 'lucide-react';
import { formatUnits } from 'viem';

// Contract Addresses
const STRESS_TOKEN = '0xA1D1B5ee47886f745707213C65073ff0BC61d7C7';

function App() {
  const { address, isConnected } = useAccount();
  const { connect } = useConnect();
  const { disconnect } = useDisconnect();

  // Mock data for initial state (since real-time events need a sub-indexer or complex hooks)
  const [riskScore] = useState(42);
  const [currentFee] = useState(0.35);

  const { data: balance } = useReadContract({
    address: STRESS_TOKEN as `0x${string}`,
    abi: [
      {
        name: 'balanceOf',
        type: 'function',
        stateMutability: 'view',
        inputs: [{ name: 'account', type: 'address' }],
        outputs: [{ name: 'balance', type: 'uint256' }],
      },
    ],
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    }
  });

  const formattedBalance = balance ? formatUnits(balance as bigint, 18) : '0.00';

  return (
    <div className="app-container">
      <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '3rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <img src="/logo2-nobg.png" alt="VolVantage Logo" style={{ height: '52px', width: 'auto' }} />
          <div>
            <h1 className="neon-text" style={{ fontSize: '2rem', margin: 0 }}>VolVantage</h1>
            <p style={{ color: 'var(--text-secondary)', fontSize: '0.9rem' }}>RAD-IH Security Protocol</p>
          </div>
        </div>

        {isConnected ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
            <div className="glass-card" style={{ padding: '8px 16px', borderRadius: '12px' }}>
              <span className="status-active">Unichain Sepolia</span>
            </div>
            <button className="btn-secondary" onClick={() => disconnect()}>
              {address?.slice(0, 6)}...{address?.slice(-4)}
            </button>
          </div>
        ) : (
          <button className="btn-primary" onClick={() => connect({ connector: injected() })}>
            <Wallet size={18} /> Connect Wallet
          </button>
        )}
      </header>

      <main style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: '2rem' }}>
        {/* Risk Dashboard */}
        <section className="glass-card" style={{ padding: '2rem', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
          <h2 style={{ alignSelf: 'flex-start', marginBottom: '1.5rem', display: 'flex', alignItems: 'center', gap: '10px' }}>
            <Activity color="var(--accent-purple)" /> Risk Intelligence
          </h2>

          <div style={{ position: 'relative', width: '200px', height: '200px', margin: '1rem 0' }}>
            <svg width="200" height="200" viewBox="0 0 100 100">
              <circle cx="50" cy="50" r="45" fill="none" stroke="rgba(255,255,255,0.05)" strokeWidth="8" />
              <circle
                cx="50" cy="50" r="45"
                fill="none"
                stroke="var(--accent-cyan)"
                strokeWidth="8"
                strokeDasharray="283"
                strokeDashoffset={283 - (283 * riskScore) / 100}
                strokeLinecap="round"
                style={{ transition: 'stroke-dashoffset 1s ease-out', transform: 'rotate(-90deg)', transformOrigin: '50% 50%' }}
              />
            </svg>
            <div style={{ position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)', textAlign: 'center' }}>
              <span style={{ fontSize: '3rem', fontWeight: 800 }}>{riskScore}</span>
              <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>RISK INDEX</p>
            </div>
          </div>
          <p style={{ color: 'var(--text-secondary)', textAlign: 'center', marginTop: '1rem' }}>
            Active monitoring of toxic volatility and LP stress.
          </p>
        </section>

        {/* Dynamic Fees */}
        <section className="glass-card" style={{ padding: '2rem' }}>
          <h2 style={{ marginBottom: '1.5rem', display: 'flex', alignItems: 'center', gap: '10px' }}>
            <Zap color="var(--accent-cyan)" /> Real-time Fee Adjust
          </h2>
          <div style={{ margin: '2rem 0' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
              <span style={{ color: 'var(--text-secondary)' }}>Base Fee</span>
              <span>0.30%</span>
            </div>
            <div style={{ background: 'rgba(255,255,255,0.1)', height: '4px', borderRadius: '2px', marginBottom: '2rem' }}>
              <div style={{ background: 'white', width: '30%', height: '100%', borderRadius: '2px' }} />
            </div>

            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
              <span className="neon-text">Adjusted RAD-IH Fee</span>
              <span className="neon-text" style={{ fontSize: '1.5rem' }}>{currentFee}%</span>
            </div>
            <div style={{ background: 'rgba(0, 242, 254, 0.1)', height: '8px', borderRadius: '4px' }}>
              <div style={{ background: 'linear-gradient(90deg, var(--accent-cyan), var(--accent-purple))', width: `${(currentFee / 1) * 100}%`, height: '100%', borderRadius: '4px', boxShadow: '0 0 10px var(--accent-cyan)' }} />
            </div>
          </div>
          <div className="glass-card" style={{ padding: '15px', background: 'rgba(0, 242, 254, 0.05)', borderRadius: '12px', fontSize: '0.9rem' }}>
            High-risk periods trigger fee escalation to protect LP capital from toxic order flow.
          </div>
        </section>

        {/* Rewards */}
        <section className="glass-card" style={{ padding: '2rem' }}>
          <h2 style={{ marginBottom: '1.5rem', display: 'flex', alignItems: 'center', gap: '10px' }}>
            <TrendingUp color="var(--accent-magenta)" /> Performance & Rewards
          </h2>
          <div style={{ textAlign: 'center', margin: '2rem 0' }}>
            <p style={{ color: 'var(--text-secondary)', fontSize: '0.9rem', marginBottom: '10px' }}>Your vSTRESS Accumulation</p>
            <h3 style={{ fontSize: '2.5rem', marginBottom: '20px' }}>
              {isConnected ? Number(formattedBalance).toFixed(2) : '—'} <span style={{ fontSize: '1rem', color: 'var(--text-secondary)' }}>vSTRESS</span>
            </h3>
            <button className="btn-primary" style={{ width: '100%' }} disabled={!isConnected}>
              Claim Rewards
            </button>
          </div>
          <div style={{ borderTop: '1px solid var(--glass-border)', paddingTop: '1.5rem' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', opacity: 0.8 }}>
              <span>Pool Utilization</span>
              <span>12.4%</span>
            </div>
          </div>
        </section>
      </main>

      <footer style={{ marginTop: 'auto', paddingTop: '4rem', paddingBottom: '2rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center', opacity: 0.6 }}>
        <p>© 2026 VolVantage Protocol | Unichain Sepolia</p>
        <div style={{ display: 'flex', gap: '20px' }}>
          <a href="#" style={{ color: 'white', textDecoration: 'none' }}><Github size={20} /></a>
          <a href="#" style={{ color: 'white', textDecoration: 'none' }}>Docs</a>
        </div>
      </footer>
    </div>
  );
}

export default App;
