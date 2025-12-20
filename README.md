# My EPBuddy

**Your Air Force EPB Writing Assistant**

My EPBuddy is a web application that helps Air Force enlisted supervisors (primarily SSgt/TSgt) and their subordinates track accomplishments and generate high-quality, myEval-ready Enlisted Performance Brief (EPB) narrative statements compliant with AFI 36-2406.

## Features

### Core Functionality
- 🔐 **Authentication** - Email/password and Google OAuth via Supabase Auth
- 👥 **Role-Based Access** - Supervisor and subordinate roles with proper permissions
- 📝 **Accomplishment Tracking** - Structured entries with action verbs, details, impact, and metrics
- ✨ **AI-Powered Generation** - Generate EPB statements using GPT-4, Claude, Gemini, or Grok
- 📊 **Team Management** - Supervisors can manage and track subordinate progress
- 📋 **myEval Ready** - Clean, plain-text output with character counting (≤350)

### Technical Features
- 🔑 **User API Keys** - Bring your own API keys for each provider (encrypted storage)
- ⚙️ **Admin Config** - Dynamic EPB configuration including prompts and MPAs
- 📱 **Responsive Design** - Works on desktop, tablet, and mobile
- 🌙 **Dark Mode** - System-aware theme switching

## Tech Stack

- **Framework**: Next.js 15+ (App Router)
- **Language**: TypeScript
- **Styling**: Tailwind CSS + shadcn/ui (Mira preset)
- **Database**: Supabase (PostgreSQL)
- **Authentication**: Supabase Auth
- **AI**: Vercel AI SDK (OpenAI, Anthropic, Google, xAI)
- **State Management**: Zustand
- **Deployment**: Vercel

## Getting Started

### Prerequisites

- Node.js 18+ 
- npm or pnpm
- Supabase account
- API keys for at least one AI provider (OpenAI, Anthropic, Google, or xAI)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/myepbuddy.git
cd myepbuddy
```

2. Install dependencies:
```bash
npm install
```

3. Copy the environment file:
```bash
cp .env.example .env.local
```

4. Configure your environment variables in `.env.local`:
```env
NEXT_PUBLIC_SUPABASE_URL=your_supabase_project_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_supabase_service_role_key
NEXT_PUBLIC_APP_URL=http://localhost:3000

# Fallback LLM API Keys
OPENAI_API_KEY=your_openai_api_key
ANTHROPIC_API_KEY=your_anthropic_api_key
GOOGLE_GENERATIVE_AI_API_KEY=your_google_api_key
XAI_API_KEY=your_xai_grok_api_key
```

### Database Setup

1. Create a new Supabase project at [supabase.com](https://supabase.com)

2. Run the migrations:
```bash
# Local development
npm run db:push:local

# Production
npm run db:push:remote
```

Or manually run the SQL files in `supabase/migrations/` in order:
- `001_initial_schema.sql` - Creates tables and functions
- `002_rls_policies.sql` - Sets up Row Level Security

3. Enable Google OAuth in Supabase Dashboard:
   - Go to Authentication > Providers
   - Enable Google provider
   - Configure OAuth credentials

### Running Locally

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

## User Guide

### For All Users

#### Adding Accomplishments
1. Navigate to **Entries** from the sidebar
2. Click **New Entry**
3. Fill in the form:
   - **Date**: When the accomplishment occurred
   - **MPA**: Major Performance Area (Executing Mission, Leading People, etc.)
   - **Action Verb**: Strong verb describing what you did (Led, Managed, etc.)
   - **Details**: What you accomplished
   - **Impact**: The results or outcome
   - **Metrics**: Quantifiable numbers (optional but recommended)

#### Generating EPB Statements
1. Go to **Generate EPB**
2. Select the ratee (yourself or a subordinate)
3. Choose an AI model
4. Click **Generate EPB Statements**
5. Review the generated statements
6. Copy individual statements or download all as text

### For Supervisors

#### Adding Team Members
1. Navigate to **My Team**
2. Click **Add Subordinate**
3. Enter their email address (they must have signed up first)
4. They will appear in your team list

#### Managing Subordinate Entries
- View all subordinate entries from the **Entries** page
- Use the filter dropdown to select a specific subordinate
- Create entries on behalf of subordinates

### Adding Your Own API Keys

1. Go to **Settings > API Keys**
2. Enter your API keys for any provider:
   - OpenAI (for GPT-4o, GPT-4o Mini)
   - Anthropic (for Claude models)
   - Google (for Gemini models)
   - xAI (for Grok)
3. Click **Save API Keys**

Your keys are encrypted before storage and only decrypted during generation.

### Admin Configuration

Administrators can customize EPB settings at `/admin/config`:

- **Max Characters**: Default statement character limit
- **SCOD Date**: Static Closeout Date
- **Cycle Year**: Current evaluation year
- **Major Performance Areas**: Add/remove MPAs
- **Style Guidelines**: Writing guidelines for AI
- **System Prompt**: Full AI prompt template
- **Rank Verb Progression**: Rank-appropriate verbs

## Deployment to Vercel

1. Push your code to GitHub

2. Connect to Vercel:
   - Go to [vercel.com](https://vercel.com)
   - Import your GitHub repository
   - Configure environment variables
   - Deploy

3. Configure Supabase for production:
   - Update OAuth redirect URLs
   - Ensure RLS policies are active

## Project Structure

```
src/
├── app/
│   ├── (app)/           # Protected app routes
│   │   ├── dashboard/
│   │   ├── entries/
│   │   ├── generate/
│   │   ├── team/
│   │   ├── settings/
│   │   └── admin/
│   ├── (auth)/          # Auth routes
│   │   ├── login/
│   │   └── signup/
│   ├── api/
│   │   └── generate/    # AI generation endpoint
│   └── auth/
│       └── callback/    # OAuth callback
├── components/
│   ├── entries/         # Entry-related components
│   ├── layout/          # App layout components
│   ├── providers/       # Context providers
│   └── ui/              # shadcn/ui components
├── lib/
│   ├── supabase/        # Supabase clients
│   ├── constants.ts
│   └── utils.ts
├── stores/              # Zustand stores
└── types/               # TypeScript types
```

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL | Yes |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon key | Yes |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service role key | Yes |
| `NEXT_PUBLIC_APP_URL` | Your app URL | Yes |
| `OPENAI_API_KEY` | OpenAI API key (fallback) | Recommended |
| `ANTHROPIC_API_KEY` | Anthropic API key (fallback) | Optional |
| `GOOGLE_GENERATIVE_AI_API_KEY` | Google AI key (fallback) | Optional |
| `XAI_API_KEY` | xAI/Grok API key (fallback) | Optional |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Disclaimer

This application is not affiliated with, endorsed by, or connected to the U.S. Air Force, Department of Defense, or any government entity. It is a personal productivity tool designed to assist with EPB preparation.

---

Built with ❤️ for Air Force supervisors and their teams.

