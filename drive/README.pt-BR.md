# Google Drive

Buscar os arquivos de um Google Drive e lê-los como texto, a partir de um agente do Pepe. Só leitura.

```bash
pepe plugin install @jhonathas/drive
```

## Ferramentas

| Ferramenta | O que faz | Altera o Drive? |
|---|---|---|
| `drive_search` | Busca arquivos e pastas pelo nome ou pelo texto, lista uma pasta, filtra por tipo (doc, sheet, slides, pdf, folder) | não |
| `drive_get_file` | Lê um arquivo como texto: um Google Doc ou apresentação como texto simples, uma planilha como CSV (a primeira aba), um arquivo de texto como ele é | não |

Os outros tipos (PDF, imagens, vídeos) devolvem só os detalhes: nome, tipo, tamanho, link. Ler o texto de um PDF ainda não é coberto.

## Configurar (uns 10 minutos)

O plugin entra como uma **conta de serviço**: uma conta-robô com e-mail próprio. Ela **não enxerga nada até você compartilhar**, então o que você compartilha é exatamente o que o agente pode ler. Não há tela de consentimento nem token para renovar na mão.

1. **Abra um projeto no Google Cloud.** Vá em <https://console.cloud.google.com> e escolha ou crie um projeto (um gratuito basta).
2. **Ligue a API do Drive.** **APIs & Services** → **Library** → procure **Google Drive API** → **Enable**.
3. **Crie a conta de serviço.** **IAM & Admin** → **Service Accounts** → **Create service account**. Dê um nome (por exemplo, "pepe-drive"). Ela não precisa de nenhum papel. Crie.
4. **Crie a chave dela.** Abra a conta → **Keys** → **Add key** → **Create new key** → **JSON**. Um arquivo é baixado. Guarde em segredo: ele é a senha da conta.
5. **Compartilhe o que ela deve ler.** Copie o e-mail da conta (parecido com `pepe-drive@seu-projeto.iam.gserviceaccount.com`). No Drive, abra cada pasta ou arquivo que o agente deve alcançar, escolha **Compartilhar**, cole esse e-mail e dê acesso de **Leitor**. Compartilhar uma pasta compartilha tudo dentro dela, então uma pasta costuma bastar. Para um **drive compartilhado**, adicione o e-mail como membro.
6. **Preencha o plugin.** No dashboard do Pepe abra **Plugins**, ache o **drive** e escolha **Configurar**:

   | Campo | O que colocar |
   |---|---|
   | Service account key | Qualquer uma destas: o conteúdo do arquivo JSON colado; o caminho do arquivo na máquina onde o Pepe roda (como `/data/keys/pepe-drive.json`); ou `${GOOGLE_SERVICE_ACCOUNT}` com o JSON no ambiente do servidor do Pepe |

   A mesma configuração pode vir do ambiente: `GOOGLE_SERVICE_ACCOUNT`.
7. **Dê as ferramentas a um agente.** Ele só tem as que você listar:

   ```bash
   pepe agent tools meu-agente --add drive_search,drive_get_file
   ```
8. **Teste.** Peça ao agente: *"liste os arquivos do Drive"*, depois *"leia o documento do plano"*. Também dá para entregar o endereço de um arquivo ou de uma pasta.

Se algo estiver errado, a ferramenta diz o quê: o Google não aceitou a conta de serviço (a mensagem traz o motivo do Google, e uma chave errada ou vencida é o mais comum), a API do Drive não está ligada, o arquivo não está compartilhado com o e-mail da conta (a mensagem diz), ou o Google está limitando o uso (a mensagem diz quanto esperar).

## Mantenha seguro

- **Ele só lê, e só o que você compartilhou.** Compartilhe o menor conjunto de pastas que o agente precisa: esse é o limite de verdade. O plugin pede ao Google acesso só de leitura, então nem um erro consegue alterar um arquivo.
- **Toda ferramenta pergunta antes de rodar**, a não ser que você a liste no `auto_approve` do agente. Ler é de baixo risco, então pré-aprovar as duas é razoável.
- **O que volta do Drive foi escrito por quem pode editar o arquivo**, então chega ao modelo marcado como texto citado, nunca como instrução. Cuidado ao dar muitas outras ferramentas a um agente que lê documentos compartilhados.
- **Trate o arquivo da chave como uma senha.** Prefira um caminho no servidor ou uma variável de ambiente a colar o JSON no formulário, e nunca o ponha num repositório.

## Observações

- Um texto é cortado em 20.000 caracteres (a ferramenta avisa). Um arquivo de texto com mais de 1 MB não é lido.
- Uma planilha é lida como CSV só da primeira aba.
- A busca casa o nome e o texto dentro dos arquivos (a busca de texto completo do Google), com as edições mais recentes primeiro.
- A conta de serviço tem um Drive próprio e vazio: ela não enxerga o seu a menos que você compartilhe.
- A instalação mostra um aviso `caution` da varredura do Pepe: o plugin lê variáveis de ambiente, usa a rede e assina uma requisição com a chave privada da conta. É para isso que ele serve.
- A proteção extra para o texto que vem do Drive (a execução deixa de honrar o `auto_approve` depois de ler um arquivo) exige um Pepe que conheça o `outside_content?/0`, da versão seguinte à 0.20. Num Pepe mais antigo o plugin funciona e ainda marca o texto como citado, mas as ferramentas pré-aprovadas continuam aprovadas, então não pré-aprove nada arriscado para um agente que lê documentos compartilhados.

---

**In English:** [README.md](https://github.com/pepe-agent/plugins/blob/main/drive/README.md)
