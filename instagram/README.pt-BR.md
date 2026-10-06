# Instagram

Ver uma conta do Instagram e os posts recentes, e publicar uma foto, um carrossel ou um reel, a partir de um agente do Pepe. Usa a API oficial da Meta (Instagram Graph API).

```bash
pepe plugin install @jhonathas/instagram
```

Para uma conta **Business ou Creator** (uma conta pessoal não aceita publicação pela API).

## Ferramentas

| Ferramenta | O que faz | Altera o Instagram? |
|---|---|---|
| `instagram_account` | Mostra a conta (nome, seguidores, posts) e quantos posts ainda pode publicar pela API nas últimas 24 horas | não |
| `instagram_recent_posts` | Lista os últimos posts com tipo, data, curtidas, comentários e link | não |
| `instagram_publish_photo` | Publica uma foto com legenda | **sim, público na hora** |
| `instagram_publish_carousel` | Publica um carrossel de 2 a 10 fotos com legenda | **sim, público na hora** |
| `instagram_publish_reel` | Publica um reel (espera o Instagram processar o vídeo antes) | **sim, público na hora** |

A API do Instagram não tem rascunhos: a publicação vai ao ar imediatamente, e este plugin não consegue desfazer um post. Por isso a publicação vem desligada e cada uma pergunta antes.

## O que você precisa antes de começar

- Uma conta do Instagram **Business ou Creator**, **ligada a uma Página do Facebook**. (No app do Instagram: Configurações → Tipo de conta e ferramentas → mudar para conta profissional. Depois ligue uma Página nas configurações da Página, em contas vinculadas.)
- Uma conta de **desenvolvedor da Meta** (<https://developers.facebook.com>) e um **app** lá.
- **Um endereço público para cada foto e vídeo.** O Instagram baixa a mídia sozinho, então o arquivo precisa estar acessível na internet num endereço `https://` (um bucket, o Cloudflare R2, qualquer hospedagem). O plugin recebe esses endereços; ele não envia arquivos.

## Configurar (uns 20 a 30 minutos, uma vez)

A Meta muda as telas e os nomes das permissões com frequência. Trate estes passos como um mapa e confira na documentação da Meta sobre a Instagram Graph API.

1. **Crie um app.** Em <https://developers.facebook.com/apps> escolha **Create app**, selecione um caso de uso que permita adicionar a API do Instagram (o tipo **Business** é o usual) e adicione o produto **Instagram** (Instagram API with Facebook login).
2. **Gere um token com as permissões certas.** Abra o Graph API Explorer (<https://developers.facebook.com/tools/explorer>), escolha o seu app e gere um **User access token** com `instagram_basic`, `instagram_content_publish`, `pages_show_list` e `pages_read_engagement`. Enquanto o app está em modo **Development**, quem tem papel no app (você, como administrador) pode usar essas permissões nas próprias contas sem a revisão de app da Meta.
3. **Faça o token durar.** O token do Explorer dura cerca de uma hora. Troque-o por um de longa duração (60 dias) com o id e o segredo do app, e depois peça a sua Página a `me/accounts`: o **Page access token** que ela devolve, obtido de um token de usuário de longa duração, não expira. (Ou crie um **System User** no Meta Business Suite, dê a ele a sua Página e a conta do Instagram e gere o token dele, que também não expira.) A documentação da Meta descreve os dois jeitos.
4. **Descubra o id da conta do Instagram.** Com esse token, pergunte à Página qual é a conta: `GET /{id-da-pagina}?fields=instagram_business_account`. O número em `instagram_business_account.id` (como `17841400000000000`) é o id. **Não** é o @nome.
5. **Preencha o plugin.** No dashboard do Pepe abra **Plugins**, ache o **instagram** e escolha **Configurar**:

   | Campo | O que colocar |
   |---|---|
   | Access token | O token, escrito como `${INSTAGRAM_ACCESS_TOKEN}`, com o valor real no ambiente do servidor do Pepe, para ele nunca ficar no arquivo de configuração |
   | Instagram account id | O número do passo 4 |
   | Allow publishing | `no` (o padrão) significa só leitura. Coloque `yes` para permitir que o agente publique |
   | Graph API version | Opcional. Como `v23.0`. Vazio usa o padrão do plugin |

   As mesmas configurações podem vir do ambiente: `INSTAGRAM_ACCESS_TOKEN`, `INSTAGRAM_USER_ID`, `INSTAGRAM_WRITES` (`yes`), `INSTAGRAM_API_VERSION`.
6. **Dê as ferramentas a um agente.** Ele só tem as que você listar:

   ```bash
   pepe agent tools meu-agente --add instagram_account,instagram_recent_posts,instagram_publish_photo,instagram_publish_carousel,instagram_publish_reel
   ```
7. **Teste, lendo primeiro.** Peça ao agente: *"mostre a conta do Instagram"*, depois *"liste os últimos 5 posts"*. Só então coloque *Allow publishing* em `yes` e tente um post, com uma foto de um endereço público que você controla.

Se algo estiver errado, a ferramenta diz o quê: o token expirou ou foi revogado (crie outro), falta uma permissão, o Instagram não conseguiu baixar a foto (a mensagem dele diz por quê), o vídeo não pôde ser processado, ou o Instagram está limitando o uso.

## Mantenha seguro

- **Publicar fica desligado até você ligar** (*Allow publishing*), e **toda publicação pergunta antes**, a não ser que você pré-aprove. Não pré-aprove as três ferramentas de publicar: um post é público no instante em que sai, e a API não o desfaz. A pergunta de aprovação mostra a legenda e o endereço da mídia.
- Ler (`instagram_account`, `instagram_recent_posts`) é de baixo risco, então pré-aprovar essas é razoável.
- **O que volta do Instagram foi escrito por quem pode postar na conta**, então chega ao modelo marcado como texto citado, nunca como instrução.
- O Instagram permite cerca de 100 posts publicados pela API por conta em 24 horas, e um carrossel conta como um. O `instagram_account` mostra o que sobrou.
- Use um **token só para o Pepe** e mantenha-o fora de repositórios. Um token vazado pode publicar na sua conta.

## Observações

- As fotos precisam ser JPEG. O Instagram tem regras de tamanho e formato (as fotos de um carrossel devem ter o mesmo formato) e de formato de vídeo; estão na documentação da Meta, e um arquivo recusado volta com a mensagem do próprio Instagram.
- Um reel pode levar um minuto para ser processado. O plugin espera até cerca de um minuto e, se o Instagram não terminou, avisa e **não publica**; tente de novo mais tarde.
- Uma legenda pode ter até 2.200 caracteres (hashtags incluídas); mais que isso é recusado antes de enviar qualquer coisa.
- A proteção extra para o texto que vem do Instagram (a execução deixa de honrar o `auto_approve` depois de ler a conta ou os posts) exige um Pepe que conheça o `outside_content?/0`, da versão seguinte à 0.20. Num Pepe mais antigo o plugin funciona e ainda marca o texto como citado.
- A instalação mostra um aviso `caution` da varredura do Pepe: o plugin lê variáveis de ambiente (para o token) e usa a rede. É para isso que ele serve.

---

**In English:** [README.md](https://github.com/pepe-agent/plugins/blob/main/instagram/README.md)
