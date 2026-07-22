# WinDebloat

**Deixe seu Windows mais limpo, com segurança**

[![Licença](https://img.shields.io/badge/Licen%C3%A7a-Apache%202.0-0078D4?style=flat-square&logo=apache&logoColor=white)](LICENSE)
[![Plataforma](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=flat-square&logo=windows&logoColor=white)](#requisitos)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?style=flat-square&logo=powershell&logoColor=white)](#requisitos)
[![Versão](https://img.shields.io/badge/Vers%C3%A3o-1.2.0-5C2D91?style=flat-square)](https://github.com/edsilas/WinDebloat/releases)


---

**Aplica-se a:** Windows 10 · Windows 11 (64 bits)

Seu computador veio de fábrica cheio de aplicativos que você nunca pediu — jogos,
apps de notícias, propaganda no Menu Iniciar? O **WinDebloat** remove esse excesso
para você, sem colocar em risco nada que seja importante para o funcionamento do
Windows.

## Neste artigo

- [Visão geral](#visão-geral)
- [Requisitos](#requisitos)
- [Introdução](#introdução)
- [Referência do Launcher](#referência-do-launcher)
- [Guia de uso](#guia-de-uso)
- [Reverter alterações](#reverter-alterações)
- [Perguntas frequentes](#perguntas-frequentes)
- [Solucionar problemas](#solucionar-problemas)
- [Recomendações](#recomendações)
- [Referência técnica](#referência-técnica)
- [Licença e autoria](#licença-e-autoria)
- [Próximas etapas](#próximas-etapas)

---

## Visão geral

### O que o WinDebloat faz

Ele remove aplicativos pré-instalados que a maioria das pessoas não usa:

| Categoria | Exemplos |
| --- | --- |
| Jogos e extras da Xbox | Game Bar, Solitaire, serviços de jogos |
| Apps de notícias e clima da Bing | News, Weather, Sports, Finance |
| Apps pouco usados | Skype, Cortana, Clipchamp, Paint 3D, Visualizador 3D, Mapas, Gravador de Som, Filmes e TV, Groove Música |
| Propaganda disfarçada | Sugestões no Menu Iniciar, apps "patrocinados" que se instalam sozinhos, conteúdo promocional |

Além de remover, ele **impede que esses apps voltem sozinhos** — o Windows tem o
hábito de reinstalar alguns deles, e o WinDebloat desliga esse comportamento.

> [!NOTE]
> A lista completa do que será removido aparece na tela durante a simulação,
> antes de qualquer alteração. Você sempre vê primeiro e decide depois.

### O que ele NUNCA remove

| Fica no lugar | Por quê |
| --- | --- |
| **Windows Update** | Seu computador continua recebendo atualizações normalmente |
| **Microsoft Store** | Você pode reinstalar qualquer app removido, de graça, quando quiser |
| **Antivírus (Defender), Firewall e SmartScreen** | Sua proteção continua completa |
| **Login e contas** (senha, PIN, biometria, conta Microsoft, redes corporativas) | Você continua entrando no PC normalmente |
| **Fotos, Bloco de Notas e Paint** | Os apps úteis do dia a dia permanecem |
| **Acessibilidade** (Narrador e recursos de assistência) | Nada de acessibilidade é tocado |
| **Recuperação do sistema e BitLocker** | Os recursos de emergência e criptografia ficam intactos |

### Como a segurança é garantida

O WinDebloat foi construído em camadas de proteção:

1. **Modo simulação primeiro.** Por padrão, ele apenas mostra o que faria, sem
   mudar absolutamente nada. Você revisa e só executa de verdade se quiser.
2. **Lista de proteção interna.** Mesmo que algo entrasse por engano na lista de
   remoção, um filtro de segurança barra qualquer componente essencial.
3. **Backup automático antes de tudo.** Ele cria um ponto de restauração do
   Windows (uma "fotografia" do sistema, que permite voltar atrás), salva cópias
   das configurações que serão alteradas e anota a lista completa de apps antes
   e depois.
4. **Verificação final.** Ao terminar, confere um por um se os componentes
   essenciais continuam presentes e avisa se algo estiver fora do esperado.
5. **Cem por cento offline.** Não acessa a internet, não envia dados e não
   instala nada de terceiros.

---

## Requisitos

| Requisito | Detalhes |
| --- | --- |
| Sistema operacional | Windows 10 ou Windows 11, versão de 64 bits (a própria ferramenta confere e avisa se não for) |
| Conta de usuário | Permissão de **administrador** — se o computador é seu e você o configurou, sua conta provavelmente já é |
| PowerShell | Windows PowerShell 5.1 (já incluído no Windows) ou PowerShell 7+ — **nenhuma instalação é necessária** |
| Internet | Não é necessária: a ferramenta é totalmente local |
| Programas adicionais | Nenhum |

---

## Introdução

### Baixar e preparar a ferramenta

Siga cada passo na ordem, sem pular nenhum:

1. **Baixe o projeto.** Nesta página do GitHub, clique no botão verde
   **Code** e depois em **Download ZIP**. O arquivo (algo como
   `WinDebloat-main.zip`) será salvo na sua pasta **Downloads**.

2. **Extraia o ZIP.** Abra a pasta Downloads, clique com o **botão direito** no
   arquivo baixado e escolha **Extrair Tudo...**. Na janela que abrir, clique em
   **Extrair**. Uma nova pasta será criada com os arquivos do projeto.

3. **Confira o conteúdo.** Dentro da pasta extraída devem estar, entre outros,
   os arquivos **`Launcher.bat`** e **`Core.ps1`**. Esses dois precisam ficar
   **sempre juntos, na mesma pasta**. Se quiser, mova a pasta inteira para um
   lugar definitivo (por exemplo, Documentos) — mas mova a pasta inteira, nunca
   os arquivos separados.

4. **Desbloqueie os arquivos (recomendado).** O Windows marca arquivos vindos
   da internet, o que pode gerar avisos extras. Para evitar isso:
   1. Clique com o **botão direito** em `Launcher.bat` e escolha **Propriedades**.
   2. Na parte de baixo da aba **Geral**, se existir uma caixa escrita
      **Desbloquear**, marque-a e clique em **OK**.
   3. Repita o mesmo para o arquivo `Core.ps1`.
   4. Se a caixa "Desbloquear" não aparecer, está tudo certo — siga em frente.

> [!IMPORTANT]
> Não execute nada de dentro do ZIP sem extrair. O Windows abre ZIPs como se
> fossem pastas, mas os programas não funcionam corretamente lá de dentro.

Pronto. Não existe "instalação": o programa roda direto da pasta.

---

## Referência do Launcher

O **Launcher** é a porta de entrada do WinDebloat: um menu simples que cuida de
tudo para você — pede a permissão de administrador, prepara o ambiente e executa
a limpeza no modo que você escolher.

### Avisos do Windows na abertura

Ao dar **duplo clique em `Launcher.bat`**, o Windows pode mostrar até dois
avisos, nesta ordem — ambos são normais:

1. **Aviso do SmartScreen** — tela azul escrita "O Windows protegeu o
   computador". Aparece porque o arquivo veio da internet e não tem assinatura
   digital de uma empresa. Clique em **Mais informações** e depois em
   **Executar assim mesmo**. Esse aviso costuma aparecer apenas na primeira vez
   (e não aparece se você desbloqueou os arquivos na preparação).
2. **Controle de Conta de Usuário** — janela perguntando "Deseja permitir que
   este aplicativo faça alterações no seu dispositivo?". Clique em **Sim** — é
   a permissão de administrador, necessária para remover apps do sistema.

### O menu

Em seguida, uma janela preta se abre com este menu:

```
============================================
   WinDebloat
============================================
   [1] Simulacao (Dry Run) - nao altera nada   <-- recomendado primeiro
   [2] Execucao real        - aplica remocoes
   [3] Sair
============================================
   Desenvolvido por Edsilas

 Escolha uma opcao [1/2/3]:
```

Para escolher, digite o número da opção e pressione **Enter**.

> [!NOTE]
> Ao final da opção 1 ou 2, o programa **não fecha**: ele mostra o resultado e
> volta automaticamente ao menu, permitindo uma nova escolha. Para encerrar,
> use sempre a opção 3.

### Opção 1 — Simulação (Dry Run)

Um "ensaio geral": o programa percorre todo o processo e mostra na tela, linha
por linha, exatamente o que faria — mas **não altera nada** no computador. É por
aqui que você deve começar, sempre. Ao terminar, o programa volta ao menu. O
passo a passo completo está em
[Etapa 1: rodar a simulação](#etapa-1-rodar-a-simulação-obrigatória-antes-de-tudo).

### Opção 2 — Execução real

A limpeza de verdade: cria os backups, remove os apps e aplica os bloqueios de
reinstalação. Exige uma confirmação extra (digitar `SIM`) como trava contra
execuções acidentais. Ao terminar, o programa volta ao menu. O passo a passo
completo está em
[Etapa 3: executar a limpeza](#etapa-3-executar-a-limpeza-de-verdade).

### Opção 3 — Sair

Encerra o programa. É a **única forma de fechar o Launcher**: as opções 1 e 2
sempre retornam ao menu ao final. Nenhuma alteração é feita ao sair.

### Modo direto (opcional)

O Launcher também aceita o modo direto, sem menu. Abra o Prompt de Comando na
pasta do programa e digite:

```
Launcher.bat dry     (simulação)
Launcher.bat real    (execução real)
```

O funcionamento e as confirmações são os mesmos. A diferença é que, no modo
direto, o programa **encerra ao final** (com o código de resultado), em vez de
voltar ao menu — comportamento adequado para uso em scripts e automação.

---

## Guia de uso

### Etapa 1: rodar a simulação (obrigatória antes de tudo)

A simulação mostra tudo o que a ferramenta faria, sem tocar em nada. Siga:

1. Dê **duplo clique em `Launcher.bat`**.
2. Se o aviso azul do SmartScreen aparecer, clique em **Mais informações** e
   depois em **Executar assim mesmo**.
3. Na janela do Controle de Conta de Usuário, clique em **Sim**.
4. No menu, digite `1` e pressione **Enter**.
5. Aguarde. As mensagens vão passando na tela; a simulação costuma levar de
   alguns segundos a poucos minutos. Não feche a janela durante o processo.
6. Ao final, aparece um **resumo** com os totais: quantos apps seriam
   removidos, quantos estão protegidos, quantos não existem no seu computador
   e quantas configurações seriam ajustadas.
7. Quando aparecer a mensagem de conclusão, pressione **qualquer tecla**. O
   programa **volta ao menu principal**: escolha `3` para sair, ou deixe a
   janela aberta enquanto revisa o relatório na próxima etapa.

> [!NOTE]
> Nada foi alterado no seu computador até aqui — a simulação é apenas leitura.

### Etapa 2: revisar o que a simulação mostrou

Antes de executar de verdade, veja com calma o que foi listado:

1. Abra a pasta do WinDebloat. Você notará que uma pasta nova chamada **`Logs`**
   foi criada.
2. Dentro dela, dê **duplo clique em `Debloat.log`**. Se o Windows perguntar
   com qual programa abrir, escolha o **Bloco de Notas**.
3. Leia o relatório. Cada linha tem uma marcação que diz o que aconteceria:

   | Marcação na linha | Significado |
   | --- | --- |
   | `[SIMULAÇÃO]` | O que **seria removido ou ajustado** na execução real — esta é a lista que você deve revisar |
   | `PROTEGIDO` | Itens que o filtro de segurança **preservaria** de qualquer forma |
   | `Não encontrado neste sistema` | Apps da lista que nem existem no seu computador |

4. **Encontrou na lista um app que você usa** (por exemplo, Câmera, Alarmes ou
   Vincular ao Celular)? Você tem duas opções: seguir em frente e reinstalá-lo
   depois pela Microsoft Store (leva segundos e é grátis), ou retirá-lo da
   lista antes de executar (veja a [Referência técnica](#referência-técnica)).
5. Só avance para a próxima etapa quando estiver de acordo com a lista.

### Etapa 3: executar a limpeza de verdade

Com a lista revisada e aprovada por você, é hora de aplicar:

1. **Feche seus programas abertos** e salve seus trabalhos. Não é obrigatório,
   mas evita qualquer interferência.
2. Se a janela do WinDebloat **ainda estiver aberta no menu** (após a
   simulação), vá direto ao passo 4. Caso contrário, dê **duplo clique em
   `Launcher.bat`** novamente.
3. Passe pelos mesmos avisos: **Executar assim mesmo** (se o SmartScreen
   aparecer) e **Sim** (no Controle de Conta de Usuário).
4. No menu, digite `2` e pressione **Enter**.
5. O programa mostra um aviso de atenção e pede a confirmação final. Digite
   **`SIM`** (maiúsculas ou minúsculas) e pressione **Enter**. Qualquer outra
   resposta cancela e volta ao menu, sem alterar nada.
6. Aguarde a execução, acompanhando as etapas na tela, nesta ordem:
   1. **Backups** — criação do ponto de restauração, cópia das configurações e
      anotação da lista de apps atual;
   2. **Remoções** — cada app da lista sendo removido (linhas verdes indicam
      sucesso; eventuais falhas pontuais aparecem em vermelho e são normais em
      alguns casos — veja [Solucionar problemas](#solucionar-problemas));
   3. **Bloqueios** — configurações que impedem os apps de voltarem sozinhos;
   4. **Verificação final** — conferência de que Store, Windows Update,
      antivírus, firewall e demais componentes essenciais continuam presentes.
7. Ao final, o **resumo** mostra o que foi feito. Se a última mensagem indicar
   que a execução foi concluída, está tudo certo.
8. Pressione **qualquer tecla**. O programa volta ao menu principal — digite
   `3` e pressione **Enter** para encerrar.

### Etapa 4: depois da limpeza

1. **Reinicie o computador.** Clique em **Iniciar**, no botão **Ligar/Desligar**
   e em **Reiniciar**. Isso consolida as remoções e os bloqueios aplicados.
2. Após reiniciar, use o computador normalmente. Se sentir falta de algum app,
   veja [Reverter alterações](#reverter-alterações) — reinstalar é simples e
   rápido.
3. **Guarde a pasta `Recovery`** que foi criada dentro da pasta do WinDebloat.
   Ela contém os backups que permitem reverter as alterações. Se quiser,
   copie-a para um pen drive ou outra pasta segura.
4. Os relatórios completos ficam na pasta `Logs`, caso queira consultar o que
   foi feito ou pedir ajuda.

---

## Reverter alterações

Você tem três caminhos, do mais simples ao mais completo.

### Reinstalar um app específico

Sentiu falta de um app? Abra a **Microsoft Store** (que nunca é removida),
digite o nome do app na busca e clique em **Obter** ou **Instalar**. É grátis e
leva segundos.

### Restaurar as configurações

Na pasta `Recovery` há arquivos cujo nome começa com `Reg_`. Dê **duplo clique**
em cada um deles e confirme clicando em **Sim** nas duas perguntas que o Windows
fizer. Isso devolve as configurações alteradas ao estado original.

### Voltar o sistema inteiro no tempo

Antes de qualquer alteração, o WinDebloat cria um ponto de restauração. Para
usá-lo:

1. Clique em **Iniciar** e digite **"Criar um ponto de restauração"**.
2. Abra o resultado e, na janela que surgir, clique em
   **Restauração do Sistema...**.
3. Clique em **Avançar**, selecione o ponto chamado **WinDebloat** (com a data
   e hora da execução) e clique em **Avançar** e **Concluir**.
4. O computador reiniciará e voltará ao estado exato daquele momento.

---

## Perguntas frequentes

**Isso vai deixar meu computador mais rápido?**
Menos apps significa menos coisas iniciando junto com o Windows, menos
atualizações em segundo plano e mais espaço em disco. O ganho varia de máquina
para máquina, mas o sistema fica visivelmente mais limpo.

**Meu antivírus continua funcionando?**
Sim. Defender, Firewall e SmartScreen são intocáveis por projeto, e o programa
ainda verifica ao final se todos continuam presentes.

**Vou continuar recebendo atualizações do Windows?**
Sim, normalmente. O Windows Update não é alterado.

**O programa acessa a internet ou coleta dados?**
Não. Tudo acontece localmente, no seu computador, e você pode conferir cada
passo nos relatórios da pasta `Logs`.

**Uso o app Câmera, Alarmes ou Vincular ao Celular. Vou perdê-los?**
Eles estão na lista padrão de remoção, mas há duas saídas fáceis: reinstalar
pela Microsoft Store depois, ou retirar esses itens da lista antes de executar
(veja a [Referência técnica](#referência-técnica)).

**Preciso rodar mais de uma vez?**
Só em duas situações: depois de uma grande atualização do Windows (que às vezes
traz apps de volta) ou se criar um novo usuário e quiser garantir a limpeza.

**Funciona em qualquer idioma do Windows?**
Sim. A remoção usa o nome interno dos pacotes, que é o mesmo em todos os
idiomas.

**Posso usar no computador do trabalho?**
Se o computador é gerenciado pela empresa (domínio ou Intune), fale antes com o
setor de TI. A ferramenta preserva os componentes corporativos de login, mas a
política da empresa pode proibir alterações desse tipo.

---

## Solucionar problemas

| O que aconteceu | O que fazer |
| --- | --- |
| Apareceu a tela azul "O Windows protegeu o computador" | É o SmartScreen avisando que o arquivo veio da internet. Clique em **Mais informações** e depois em **Executar assim mesmo** |
| A janela de permissão (UAC) não apareceu e o programa fechou sozinho | Clique com o botão direito em `Launcher.bat` e escolha **Executar como administrador** |
| Apareceu "Core.ps1 nao encontrado" | Os arquivos foram separados ou o ZIP não foi extraído. Refaça a preparação em [Introdução](#introdução), mantendo tudo na mesma pasta |
| Mensagem dizendo que o ponto de restauração não foi criado | A Restauração do Sistema está desligada no seu PC. O programa continua (os outros backups são feitos). Para ativar: **Iniciar** → digite "Criar um ponto de restauração" → selecione o disco **C:** → **Configurar** → **Ativar a proteção do sistema** → **OK** — e rode a ferramenta de novo |
| Um ou outro app apareceu com "Falha ao remover" em vermelho | Normal em alguns casos: certas versões do Windows travam apps específicos (por exemplo, o Dev Home, que retorna "erro não especificado"). Nada de errado aconteceu — o item apenas permanece no sistema |
| Aviso amarelo: app "instalado apenas em outro perfil de usuário" | Em computadores com mais de uma conta, o Windows só permite remover os apps de cada usuário estando conectado na conta dele. Entre na outra conta e rode a ferramenta lá também |
| Letras estranhas ou acentos trocados na janela preta | É apenas visual e não afeta o funcionamento. Os relatórios da pasta `Logs` ficam legíveis |
| Um app removido voltou depois de uma grande atualização do Windows | Comportamento do próprio Windows em atualizações de versão. Rode o WinDebloat novamente após a atualização |
| A janela fechou e não deu tempo de ler | Tudo fica gravado. Abra `Logs\Debloat.log` com o Bloco de Notas e leia com calma |
| Preciso de ajuda para entender o que houve | Abra a pasta `Logs`: `Debloat.log` conta a história completa e `Errors.log` lista apenas os problemas. Ao pedir ajuda (ou abrir uma issue aqui no GitHub), anexe esses dois arquivos |

---

## Recomendações

> [!TIP]
> Simule antes, sempre. Custa dois minutos e elimina surpresas.

- **Reinicie após a execução real** para que tudo se assente.
- **Guarde a pasta `Recovery`** enquanto quiser manter a possibilidade de
  desfazer as alterações.
- Se for usar no computador de outra pessoa, mostre a simulação a ela antes —
  cada um sente falta de apps diferentes.

> [!WARNING]
> Não rode durante uma atualização do Windows. Termine a atualização, reinicie
> e só então execute.

---

## Referência técnica

Detalhes completos — parâmetros, arquitetura interna, códigos de saída e
compatibilidade — estão documentados nos comentários do próprio `Core.ps1`,
organizado em regiões numeradas e comentado em português. Em resumo:

| Item | Detalhes |
| --- | --- |
| Compatibilidade | Windows PowerShell 5.1 (nativo do Windows) e PowerShell 7+ (preferido automaticamente pelo Launcher, quando instalado) |
| Execução direta do núcleo | `pwsh -File .\Core.ps1 -DryRun \| -Execute [-RootDir <pasta>] [-SkipRestorePoint]` — sem parâmetros, o padrão é a simulação |
| Personalizar a lista de remoção | Edite o mapa `$TargetApps` no `Core.ps1`; para preservar um app, apague a linha correspondente antes de executar |
| Mecanismo de remoção | Dois níveis: usuários atuais e pacotes provisionados (novos usuários) |
| Anti-reinstalação | Políticas em HKLM, HKCU e no perfil padrão |
| Proteção | Filtro por expressões regulares como última linha de defesa contra remoções indevidas |

---

## Licença e autoria

**Desenvolvido por Edsilas** — Copyright © 2026 Edsilas.

Este projeto é gratuito e de código aberto, sob a **Apache License 2.0**: você
pode usar, copiar, modificar e distribuir livremente, inclusive em contextos
comerciais, mantendo os créditos. O texto completo está no arquivo
[`LICENSE`](LICENSE), e o aviso de autoria no arquivo [`NOTICE`](NOTICE).

> [!CAUTION]
> O software é fornecido "como está", sem garantias — por isso a simulação
> existe: use-a antes de qualquer execução real.

---

## Próximas etapas

- Comece pela preparação em [Introdução](#introdução).
- Rode sua primeira simulação seguindo o [Guia de uso](#guia-de-uso).
- Dúvidas ou problemas? Abra uma [issue](https://github.com/edsilas/WinDebloat/issues)
  anexando os arquivos da pasta `Logs`.

