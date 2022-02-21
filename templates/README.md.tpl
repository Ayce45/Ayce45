## Hey, I'm Ayce!
- 🔭 I’m currently working on <a href="https://link-u.nified.com/">Unified</a> and <a href="https://sertizh.fr/">Sertizh</a>
- 🌱 I’m currently learning NuxtJS, TailwindCSS, Storybook, Jest ...
- ⚡ Fun fact: I'm riding with electric skateboard

#### 👷 Check out what I'm currently working on
{{range recentContributions 5}}
- [{{.Repo.Name}}]({{.Repo.URL}}) - {{.Repo.Description}} ({{humanize .OccurredAt}})
{{- end}}

#### 🌱 My latest projects
{{range recentRepos 5}}
- [{{.Name}}]({{.URL}}) - {{.Description}}
{{- end}}

#### ⭐ Recent Stars
{{range recentStars 5}}
- [{{.Repo.Name}}]({{.Repo.URL}}) - {{.Repo.Description}} ({{humanize .StarredAt}})
{{- end}}

#### 👯 Check out some of my recent followers
{{range followers 5}}
- [{{.Login}}]({{.URL}})
{{- end}}
  
<a href="https://app.daily.dev/Ayce"><img src="https://api.daily.dev/devcards/6f27abf04ef249b1a106e3ddb7e7cda4.png?r=tkh" width="400" alt="Evan JUGE's Dev Card"/></a>
