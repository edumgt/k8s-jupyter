전체 프로세스를 flowchart 및 sequence 로 readme 에 포함시켜줘
Steer


현재 이 구조가 k8s 가 맞는지 다시 한번 확인 하고, 아니면 k8s 로 맞춰줘
Steer


이 repo 에 사용한 모든 컨테이너를 https://hub.docker.com/repositories/edumgt 에 public 하게 push 히고, 이후 pull 은 모두 https://hub.docker.com/repositories/edumgt 에서 하도록 수정변경
Steer


github actions 에서 변경 docker container 에 대한 docker hub push, 내 로컬 환경의 docker 구성으로
Steer


이후 폐쇄망에서 사용하기 위한 라이브러리 다운로드 등 모든 작업을 해줘
Steer


이걸 OVA VM 이미지로 구성할때, docker 엔진, vi 에디터, curl 등 필요로 하는 모든 솔루션 , 라이브러리 , 모듈도 미리 설치하고, OS 는 ubuntu 로 