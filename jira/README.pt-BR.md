# Jira

Buscar, ler, criar, comentar e mover cards do Jira Cloud a partir de um agente do Pepe.

```bash
pepe plugin install @jhonathas/jira
```

Só **Jira Cloud** (API REST v3). Jira Server e Data Center autenticam de outro jeito e não são cobertos.

## Ferramentas

| Ferramenta | O que faz | Altera o Jira? |
|---|---|---|
| `jira_search` | Lista os cards que casam com uma busca JQL | não |
| `jira_get_issue` | Lê um card: pessoas, etiquetas, descrição e os últimos comentários | não |
| `jira_create_issue` | Cria um card e devolve o link | sim |
| `jira_comment` | Adiciona um comentário | sim |
| `jira_transition` | Move um card no fluxo (sem destino, lista os movimentos permitidos) | sim |

## Configurar (uns 5 minutos)

1. **Crie um token de API.** Abra <https://id.atlassian.com/manage-profile/security/api-tokens>, escolha **Create API token**, dê um nome (por exemplo, "Pepe") e copie. Ele só aparece uma vez.
2. **Saiba o seu site.** É o endereço que você usa para abrir o Jira, como `suaempresa.atlassian.net` (sem `https://`).
3. **Preencha o plugin.** No dashboard do Pepe abra **Plugins**, ache o **jira** e escolha **Configurar**:

   | Campo | O que colocar |
   |---|---|
   | Jira site | `suaempresa.atlassian.net` |
   | Account e-mail | O e-mail da conta dona do token |
   | API token | O token, escrito como `${JIRA_API_TOKEN}`, com o valor real no ambiente do servidor do Pepe, para ele nunca ficar no arquivo de configuração |
   | Default project key | Opcional. Como `CNSUP`. Vale quando um card novo não diz o projeto |
   | Projects the agent may change | Opcional. Como `CNSUP, OPS`. Veja *Mantenha seguro* |

   As mesmas configurações podem vir do ambiente: `JIRA_SITE`, `JIRA_EMAIL`, `JIRA_API_TOKEN`, `JIRA_PROJECT`, `JIRA_ALLOWED_PROJECTS`.
4. **Dê as ferramentas a um agente.** Ele só tem as que você listar:

   ```bash
   pepe agent tools meu-agente --add jira_search,jira_get_issue,jira_create_issue,jira_comment,jira_transition
   ```
5. **Teste.** Peça ao agente, em qualquer canal: *"liste os cards abertos do projeto CNSUP"*. Devem voltar chaves e títulos. Depois: *"abra o CNSUP-1"*.

Se algo estiver errado, a ferramenta diz o quê: o Jira não aceitou o e-mail e o token (confira o e-mail e se o token está válido), o card não existe ou a conta não o enxerga, ou o Jira recusou um campo (a mensagem nomeia o campo).

## Mantenha seguro

- **Toda ferramenta pergunta antes de rodar**, a não ser que você a liste no `auto_approve` do agente. Uma divisão sensata é pré-aprovar as duas que só leem (`jira_search`, `jira_get_issue`) e deixar as três que escrevem perguntando.
- **Limite onde ele pode escrever.** Preencha *Projects the agent may change* e criar, comentar e mover são recusados em qualquer outro projeto. Ler não tem limite.
- **O que volta do Jira foi escrito por quem abriu o card**, então chega ao modelo marcado como texto citado, nunca como instrução. Não dê a um agente que lê chamados de clientes mais ferramentas do que ele precisa.
- Use uma **conta dedicada** para o token (um usuário de serviço), e não a de uma pessoa, para ver o que ele fez e revogar sem afetar ninguém.

## Observações

- A proteção extra para o texto que vem do Jira (a execução deixa de honrar o `auto_approve` depois de ler um card) exige um Pepe que conheça o `outside_content?/0`, da versão seguinte à 0.20. Num Pepe mais antigo o plugin funciona e ainda marca o texto como citado, mas as ferramentas pré-aprovadas continuam aprovadas, então não pré-aprove nada arriscado para um agente que lê cards.
- Descrições e comentários são o texto rico do Jira; o plugin lê como texto simples e escreve texto simples de volta (linha em branco vira parágrafo). Formatações como negrito, tabelas e menções não são geradas ao escrever.
- A busca devolve até 50 cards por chamada.
- Anexos aparecem como `[attachment]`, sem baixar.

---

**In English:** [README.md](https://github.com/pepe-agent/plugins/blob/main/jira/README.md)
